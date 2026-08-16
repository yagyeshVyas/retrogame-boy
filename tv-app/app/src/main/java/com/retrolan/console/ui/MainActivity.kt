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
import com.retrolan.console.core.LibRetro
import com.retrolan.console.network.RetroAdvertiser
import com.retrolan.console.network.RetroServer
import java.io.File

/**
 * 10-foot ROM library. D-pad navigable card grid (Android TV), SAF folder picker,
 * starts [GameActivity] with the chosen ROM. Also owns the WS server + mDNS advertise.
 *
 * RetroLAN-original (GPLv3 under /tv-app).
 */
class MainActivity : AppCompatActivity() {
    private lateinit var grid: RecyclerView
    private lateinit var status: TextView
    private lateinit var pickButton: Button
    private var adapter: RomAdapter? = null
    private var advertiser: RetroAdvertiser? = null

    private val folderPicker =
        registerForActivityResult(ActivityResultContracts.OpenDocumentTree()) { uri ->
            uri ?: return@registerForActivityResult
            val tree = contentResolver.takePersistableUriPermission(
                uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
            val roms = scanFolder(uri)
            adapter?.submit(roms)
            status.text = getString(R.string.select_rom) + " · " + roms.size + " found"
        }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)

        grid = findViewById(R.id.rom_grid)
        status = findViewById(R.id.status_text)
        pickButton = findViewById(R.id.pick_folder)

        grid.layoutManager = GridLayoutManager(this, 3)
        adapter = RomAdapter { rom ->
            val intent = Intent(this, GameActivity::class.java)
                .putExtra("romName", rom.name)
                .putExtra("romUri", rom.uri.toString())
            startActivity(intent)
        }
        grid.adapter = adapter

        pickButton.setOnClickListener { folderPicker.launch(null) }

        // LAN services
        RetroServer.start()
        advertiser = RetroAdvertiser(this).also { it.start() }
        LibRetro.coreLibraryDir = File(applicationInfo.nativeLibraryDir)
    }

    private fun scanFolder(uri: Uri): List<RomEntry> {
        val out = mutableListOf<RomEntry>()
        val kids = contentResolver.query(
            uri, arrayOf(
                android.provider.OpenableColumns.DISPLAY_NAME,
                android.provider.OpenableColumns.SIZE), null, null, null)
        kids?.use { c ->
            while (c.moveToNext()) {
                val name = c.getString(0)
                if (name != null && isRomExt(name)) {
                    out.add(RomEntry(name, uri.buildUpon().appendPath(name).build()))
                }
            }
        }
        return out
    }

    private fun isRomExt(name: String): Boolean {
        val e = name.substringAfterLast('.', "").lowercase()
        // user-owned local ROMs only; NES for the fceumm core in v1
        return e in setOf("nes", "snes", "smc", "gb", "gbc")
    }

    override fun onDestroy() {
        RetroServer.stop()
        advertiser?.stop()
        super.onDestroy()
    }
}

data class RomEntry(val name: String, val uri: Uri)
