package com.retrolan.console.ui

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.widget.Button
import android.widget.TextView
import android.widget.Toast
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
        // Fallback when the TV has no file browser (SAF picker unavailable):
        // scan the Download collection directly via MediaStore — no picker needed.
        findViewById<android.widget.Button>(R.id.scan_downloads).setOnClickListener {
            val found = scanDownloads()
            status.text = getString(R.string.select_rom) +
                " · $found game${if (found == 1) "" else "s"} from Downloads · tap OK to play"
        }
        // Scan the ENTIRE storage recursively for any playable ROM file anywhere.
        findViewById<android.widget.Button>(R.id.scan_all).setOnClickListener {
            val found = scanAllStorage()
            status.text = "Found $found game${if (found == 1) "" else "s"} on this TV · tap OK to play"
        }

        // Restore last-used folder (persistent across launches).
        prefs.getString("rom_folder", null)?.let { Uri.parse(it) }?.let {
            folderUri = it
            rescan()
        } ?: run {
            status.text = getString(R.string.no_rom_folder)
        }

        // LAN services (WebSocket for the phone controller + mDNS advertise so phones find us).
        RetroServer.romDir = java.io.File(getExternalFilesDir(null), "roms")
        RetroServer.onRomReceived = { name -> runOnUiThread { onReceivedRom(name) } }
        RetroServer.start()
        advertiser = RetroAdvertiser(this).also { it.start() }
        LibRetro.coreLibraryDir = File(applicationInfo.nativeLibraryDir)
    }

    /** A ROM was sent from the phone over Wi-Fi — add it to the library and launch it. */
    private fun onReceivedRom(name: String) {
        val file = java.io.File(java.io.File(getExternalFilesDir(null), "roms"), name)
        val rom = RomEntry(name, Uri.fromFile(file), systemFor(name))
        adapter?.submit(listOf(rom) + (adapter?.getItems() ?: emptyList()).filter { it.name != name })
        Toast.makeText(this, "Received $name — launching", Toast.LENGTH_SHORT).show()
        launch(rom)
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

    /** Friendly system name for a file — peeks inside .zip containers when possible. */
    private fun systemFor(name: String): String {
        val ext = name.substringAfterLast('.', "").lowercase()
        val coreDef = Cores.resolve(ext)
        if (coreDef != null) return coreDef.system
        return if (ext == Cores.ZIP_EXT) "Archive (ROM zip)" else "Unknown system"
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
                    out.add(RomEntry(name, uri.buildUpon().appendPath(name).build(), systemFor(name)))
                }
            }
        }
        return out.sortedBy { it.system + it.name }
    }

    /**
     * Fallback scan of the system Downloads collection via MediaStore — no SAF folder
     * picker needed. Use this when the TV has no file-browser app to handle the picker
     * intent (e.g. many ONN / Google TV boxes). Reads user-owned files only.
     */
    private fun scanDownloads(): Int {
        val out = mutableListOf<RomEntry>()
        val projection = arrayOf(
            android.provider.MediaStore.Downloads._ID,
            android.provider.MediaStore.Downloads.DISPLAY_NAME)
        try {
            contentResolver.query(
                android.provider.MediaStore.Downloads.getContentUri(
                    "external"), projection, null, null, null)?.use { c ->
                val nameCol = c.getColumnIndexOrThrow(
                    android.provider.MediaStore.Downloads.DISPLAY_NAME)
                while (c.moveToNext()) {
                    val name = c.getString(nameCol) ?: continue
                    if (!isRom(name)) continue
                    val system = systemFor(name)
                    // Openable content URI for this MediaStore entry.
                    val id = c.getLong(c.getColumnIndexOrThrow(
                        android.provider.MediaStore.Downloads._ID))
                    val uri = android.content.ContentUris.withAppendedId(
                        android.provider.MediaStore.Downloads.getContentUri("external"), id)
                    out.add(RomEntry(name, uri, system))
                }
            }
        } catch (_: Exception) {
            // Best-effort; fall back to picker if MediaStore unavailable.
        }
        adapter?.submit(out)
        if (out.isEmpty()) {
            status.text = getString(R.string.no_rom_folder) +
                " — put ROMs in Downloads or use PICK ROM FOLDER"
        }
        return out.size
    }

    /**
     * Scan the ENTIRE external storage for playable ROM files (all systems/formats).
     * Uses MediaStore File collection (indexes the whole /sdcard) + a recursive File walk
     * as a fallback, so a game file in ANY folder shows up. User-owned local files only.
     */
    private fun scanAllStorage(): Int {
        val out = LinkedHashMap<String, RomEntry>() // dedupe by name
        // 1) MediaStore File collection — indexes everything the media provider has seen.
        try {
            val uri = android.provider.MediaStore.Files.getContentUri("external")
            contentResolver.query(uri, arrayOf(
                android.provider.MediaStore.Files.FileColumns._ID,
                android.provider.MediaStore.Files.FileColumns.DISPLAY_NAME,
                android.provider.MediaStore.Files.FileColumns.DATA),
                null, null, null)?.use { c ->
                val idCol = c.getColumnIndex(android.provider.MediaStore.Files.FileColumns._ID)
                val nameCol = c.getColumnIndex(android.provider.MediaStore.Files.FileColumns.DISPLAY_NAME)
                while (c.moveToNext()) {
                    val name = c.getString(nameCol) ?: continue
                    if (!isRom(name)) continue
                    val id = if (idCol >= 0) c.getLong(idCol) else 0L
                    val uri0 = android.content.ContentUris.withAppendedId(uri, id)
                    out[name] = RomEntry(name, uri0, systemFor(name))
                }
            }
        } catch (_: Exception) {}

        // 2) Recursive File walk fallback (finds files MediaStore hasn't indexed yet).
        try {
            val root = File("/sdcard")
            if (root.exists()) walkForRoms(root, out)
        } catch (_: Exception) {}
        // 3) The app's OWN external files dir — always readable under scoped storage.
        //    (ADB-pushed ROMs placed here are seen even when MediaStore hasn't indexed them.)
        try {
            getExternalFilesDir(null)?.let { walkForRoms(it, out) }
        } catch (_: Exception) {}

        val sorted = out.values.sortedBy { it.system + it.name }
        adapter?.submit(sorted)
        if (sorted.isEmpty()) {
            status.text = "No games found — put ROM files on the TV (e.g. Downloads)"
        }
        return sorted.size
    }

    private fun walkForRoms(dir: File, out: MutableMap<String, RomEntry>) {
        val children = dir.listFiles() ?: return
        for (f in children) {
            if (f.isDirectory) {
                // skip heavy non-rom dirs (but NOT 'android' — our own ROMs live under
                // /sdcard/Android/data/com.retrolan.console/files/ and must be reachable)
                val n = f.name.lowercase()
                if (n in setOf("phone", "obb", "cache", "alarms", "notifications", "ringtones", "podcasts", "audiobooks")) continue
                walkForRoms(f, out)
            } else {
                if (isRom(f.name)) {
                    out[f.name] = RomEntry(f.name, Uri.fromFile(f), systemFor(f.name))
                }
            }
        }
    }

    private fun isRom(name: String): Boolean {
        val e = name.substringAfterLast('.', "").lowercase()
        // All supported systems' ROM extensions + containers — user-owned local files only.
        return e in Cores.allExtensions
    }

    override fun onDestroy() {
        RetroServer.stop()
        advertiser?.stop()
        super.onDestroy()
    }
}

data class RomEntry(val name: String, val uri: Uri, val system: String = "Unknown")
