package com.retrolan.console.ui

import android.annotation.SuppressLint
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.TextView
import androidx.recyclerview.widget.RecyclerView
import com.retrolan.console.R

/**
 * D-pad friendly grid adapter showing your ROM files as large cards with a system badge.
 * Card art is a placeholder (no copyrighted box art is bundled); users can later point
 * cards at their own images. Emphasizes the game title, navigable with a TV remote/DPad.
 */
class RomAdapter(
    private val onClick: (RomEntry) -> Unit,
) : RecyclerView.Adapter<RomAdapter.VH>() {

    private val items = mutableListOf<RomEntry>()

    @SuppressLint("NotifyDataSetChanged")
    fun submit(list: List<RomEntry>) { items.clear(); items.addAll(list); notifyDataSetChanged() }

    fun getItems(): List<RomEntry> = items.toList()

    class VH(view: View, private val click: (RomEntry) -> Unit) : RecyclerView.ViewHolder(view) {
        private val title: TextView = view.findViewById(R.id.rom_title)
        private val system: TextView = view.findViewById(R.id.rom_system)
        private val poster: android.widget.ImageView = view.findViewById(R.id.rom_poster)
        fun bind(rom: RomEntry) {
            title.text = prettyName(rom.name)
            system.text = rom.system
            if (rom.posterUri != null) {
                try {
                    poster.setImageURI(rom.posterUri)
                } catch (_: Exception) {
                    poster.setImageResource(R.drawable.art_placeholder)
                }
            } else {
                poster.setImageResource(R.drawable.art_placeholder)
            }
            itemView.setOnClickListener { click(rom) }
            itemView.isFocusable = true
            itemView.isClickable = true
        }

        /** "super_game_v2.nes" -> "Super Game V2" — clean title for the library. */
        private fun prettyName(fileName: String): String {
            val base = fileName.substringBeforeLast('.')
            val words = base.replace('_', ' ').replace('-', ' ').trim().split(Regex("\\s+"))
            return words.joinToString(" ") { w ->
                if (w.isEmpty()) w else w.first().uppercase() + w.drop(1)
            }
        }
    }

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): VH {
        val v = LayoutInflater.from(parent.context).inflate(R.layout.item_rom_card, parent, false)
        return VH(v, onClick)
    }
    override fun onBindViewHolder(holder: VH, position: Int) = holder.bind(items[position])
    override fun getItemCount() = items.size
}
