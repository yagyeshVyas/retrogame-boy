package com.retrolan.console.ui

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.widget.Button
import android.widget.TextView
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AppCompatActivity
import androidx.recyclerview.widget.GridLayoutManager
import androidx.recyclerview.widget.RecyclerView
import com.retrolan.console.R
import com.retrolan.console.core.Cores
import com.retrolan.console.core.LibRetro
import com.retrolan.console.network.RetroAdvertiser
import com.retrolan.console.network.RetroServer
import java.io.File

/**
 * "My ROMs" library (10-foot, D-pad navigable). You pick ONE folder of ROM files you
 * already own; the folder is persisted and auto-scanned on every launch. Games are shown
 * as large focusable cards grouped by system, tap/OK to launch.
 *
 * This app only ever LOADS user-owned local ROM files — it never bundles, downloads, or
 * links copyrighted game content. A ROM you have on your own device (e.g. in this folder)
 * is just a file on disk; RetroLAN plays it, it is not shipped inside the app.
 *
 * RetroLAN-original (GPLv3 under /tv-app).
 */
class MainActivity : AppCompatActivity() {
    private lateinit var grid: RecyclerView
    private lateinit var status: TextView
    private lateinit var pickButton: Button
    private var adapter: RomAdapter? = null
    private var advertiser: RetroAdvertiser? = null

    private val prefs by lazy { getSharedPreferences("retrolan", MODE_PRIVATE) }
    private var folderUri: Uri? = null

    private val folderPicker =
        registerForActivityResult(ActivityResultContracts.OpenDocumentTree()) { uri ->
            uri ?: return@registerForActivityResult
            contentResolver.takePersistableUriPermission(
                uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
            prefs.edit().putString("rom_folder", uri.toString()).apply()
            folderUri = uri
            rescan()
        }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)

        grid = findViewById(R.id.rom_grid)
        status = findViewById(R.id.status_text)
        pickButton = findViewById(R.id.pick_folder)

        grid.layoutManager = GridLayoutManager(this, 3)
        adapter = RomAdapter { rom -> launch(rom) }
        grid.adapter = adapter

        pickButton.setOnClickListener { folderPicker.launch(null) }

        // Restore last-used folder (persistent across launches).
        prefs.getString("rom_folder", null)?.let { Uri.parse(it) }?.let {
            folderUri = it
            rescan()
        } ?: run {
            status.text = getString(R.string.no_rom_folder)
        }

        // LAN services (WebSocket for the phone controller + mDNS advertise so phones find us).
        RetroServer.start()
        advertiser = RetroAdvertiser(this).also { it.start() }
        LibRetro.coreLibraryDir = File(applicationInfo.nativeLibraryDir)
    }

    /** Re-scan the persisted folder and refresh the grid. Never crashes on a stale URI. */
    private fun rescan() {
        val uri = folderUri ?: return
        val roms = try {
            scanFolder(uri)
        } catch (e: SecurityException) {
            // Folder permission revoked / URI stale (e.g. app data restored). Clear + re-pick.
            prefs.edit().remove("rom_folder").apply()
            folderUri = null
            adapter?.submit(emptyList())
            status.text = getString(R.string.no_rom_folder)
            return
        } catch (e: Exception) {
            // Any other query failure — degrade gracefully, let the user pick again.
            adapter?.submit(emptyList())
            status.text = getString(R.string.no_rom_folder)
            return
        }
        adapter?.submit(roms)
        val found = roms.size
        status.text = getString(
            if (found == 0) R.string.no_rom_folder else R.string.select_rom) +
            " · $found game${if (found == 1) "" else "s"} · tap OK to play"
    }

    private fun launch(rom: RomEntry) {
        val intent = Intent(this, GameActivity::class.java)
            .putExtra("romName", rom.name)
            .putExtra("romUri", rom.uri.toString())
            .putExtra("system", rom.system)
        startActivity(intent)
    }

    /** Enumerate ROM files (user-owned, local) in the chosen folder. */
    private fun scanFolder(uri: Uri): List<RomEntry> {
        val out = mutableListOf<RomEntry>()
        val kids = contentResolver.query(
            uri, arrayOf(
                android.provider.OpenableColumns.DISPLAY_NAME,
                android.provider.OpenableColumns.SIZE), null, null, null)
        kids?.use { c ->
            while (c.moveToNext()) {
                val name = c.getString(0)
                if (name != null && isRom(name)) {
                    val ext = name.substringAfterLast('.', "").lowercase()
                    val coreDef = Cores.resolve(ext)
                    val system = coreDef?.system ?: "Unknown system"
                    out.add(RomEntry(name, uri.buildUpon().appendPath(name).build(), system))
                }
            }
        }
        return out.sortedBy { it.system + it.name }
    }

    private fun isRom(name: String): Boolean {
        val e = name.substringAfterLast('.', "").lowercase()
        // All supported systems' ROM extensions — user-owned local files only.
        return e in Cores.allExtensions
    }

    override fun onDestroy() {
        RetroServer.stop()
        advertiser?.stop()
        super.onDestroy()
    }
}

data class RomEntry(val name: String, val uri: Uri, val system: String = "Unknown")
