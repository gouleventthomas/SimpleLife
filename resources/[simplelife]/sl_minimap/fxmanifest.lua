--[[
    sl_minimap — minimap propre : retire les barres VIE/ARMURE de la minimap + le réticule rouge.

    Pure remplacement d'assets : deux scaleforms streamés dans stream/ remplacent les assets natifs
    par leurs versions « sans barres » (origine : pack b2k-minimap, consolidé ici) :
        stream/minimap.gfx       -> minimap sans HP/armure
        stream/hud_reticle.gfx   -> réticule sans le rouge
    Aucun script requis (FiveM auto-charge le dossier stream/). Si tu modifies les .gfx, fais un
    restart sl_minimap + reconnecte (les assets streamés sont mis en cache au join).
]]

fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'sl_minimap'
author 'SimpleLife'
version '0.2.0'
description 'Minimap propre : retire les barres vie/armure + le réticule rouge (scaleforms streamés).'
