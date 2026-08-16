package com.retrolan.console.core

/**
 * Supported systems → libretro core mapping.
 *
 * Each entry maps a console to:
 *  - the libretro core `.so` base name it loads (placed under jniLibs/<abi>/libretro_<core>.so),
 *  - the ROM file extensions it accepts,
 *  - the number of joypad players it supports.
 *
 * Cores are GPL-licensed and NOT vendored here — obtain binaries from the cores'
 * own GPL-compliant sources and drop them into app/src/main/jniLibs/<abi>/.
 * This file is RetroLAN-original (GPLv3 under /tv-app).
 */
data class CoreDef(
    val system: String,          // friendly name shown in the UI
    val core: String,            // libretro core so base name
    val extensions: Set<String>, // ROM file extensions (lowercase)
    val players: Int = 2,
    val short: String = system.substringBefore(" ("),
)

/** Full catalog of supported systems/cores (fceumm, snes9x, gambatte, mgba, ...). */
object Cores {
    private val list = listOf(
        CoreDef("Atari 2600 (A26)", "stella", setOf("a26", "bin")),
        CoreDef("Atari 7800 (A78)", "prosystem", setOf("a78", "bin")),
        CoreDef("Atari Lynx", "handy", setOf("lnx")),
        CoreDef("Nintendo (NES)", "fceumm", setOf("nes", "fds", "unf", "unif")),
        CoreDef("Super Nintendo (SNES)", "snes9x", setOf("sfc", "smc", "fig", "swc")),
        CoreDef("Game Boy (GB)", "gambatte", setOf("gb", "dmg")),
        CoreDef("Game Boy Color (GBC)", "gambatte", setOf("gbc")),
        CoreDef("Game Boy Advance (GBA)", "mgba", setOf("gba", "agb", "mb")),
        CoreDef("Sega Genesis (Megadrive)", "genesis_plus_gx", setOf("md", "gen", "bin", "smd")),
        CoreDef("Sega CD (Mega CD)", "genesis_plus_gx", setOf("cue", "chd"), players = 2),
        CoreDef("Sega Master System (SMS)", "genesis_plus_gx", setOf("sms")),
        CoreDef("Sega Game Gear (GG)", "genesis_plus_gx", setOf("gg", "sg")),
        CoreDef("Nintendo 64 (N64)", "mupen64plus", setOf("n64", "z64", "v64")),
        CoreDef("PlayStation (PSX)", "pcsx_rearmed", setOf("cue", "chd", "pbp", "exe"), players = 2),
        CoreDef("PlayStation Portable (PSP)", "ppsspp", setOf("iso", "cso", "chd", "pbp"), players = 1),
        CoreDef("FinalBurn Neo (Arcade)", "fbneo", setOf("zip", "7z"), players = 4),
        CoreDef("Nintendo DS (NDS)", "desmume", setOf("nds"), players = 1),
        CoreDef("NEC PC Engine (PCE)", "beetle_pce_fast", setOf("pce", "sgx", "cue", "chd")),
        CoreDef("Neo Geo Pocket (NGP)", "mednafen_ngp", setOf("ngp")),
        CoreDef("Neo Geo Pocket Color (NGC)", "mednafen_ngp", setOf("ngc")),
        CoreDef("WonderSwan (WS)", "beetle_cygne", setOf("ws", "wsc")),
        CoreDef("WonderSwan Color (WSC)", "beetle_cygne", setOf("wsc")),
        CoreDef("Nintendo 3DS (3DS)", "citra", setOf("3ds", "3dsx", "cia", "cci"), players = 1),
    )

    /** Names + core ids advertised in the hello_ack (used by the controller). */
    val advertised: List<String> = list.map { "${it.system}|${it.core}" }

    val coreNames: List<String> = list.map { it.core }

    /** Containers we open and peek inside (e.g. a .zip holding one ROM). */
    const val ZIP_EXT = "zip"

    /** Pick the first core that accepts this ROM extension, else null. */
    fun resolve(extension: String): CoreDef? {
        val e = extension.lowercase()
        return list.firstOrNull { e in it.extensions }
    }

    /**
     * Detect the system for a ROM *inside* a container. Used when a .zip wraps a single
     * game file — we look at the inner file's extension to pick the right core.
     */
    fun resolveInner(innerName: String): CoreDef? =
        resolve(innerName.substringAfterLast('.', ""))

    /** All accepted ROM extensions (for the SAF picker filter). */
    val allExtensions: Set<String> = list.flatMap { it.extensions }.toSet() + ZIP_EXT

    /** Default core names shown in hello_ack (keep it compact). */
    val defaultHelloCores: List<String> = listOf(
        "fceumm", "snes9x", "gambatte", "mgba", "genesis_plus_gx",
        "mupen64plus", "pcsx_rearmed", "ppsspp", "fbneo", "desmume",
        "beetle_pce_fast", "mednafen_ngp", "beetle_cygne", "citra",
        "stella", "prosystem", "handy",
    )
}
