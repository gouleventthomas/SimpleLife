fx_version 'cerulean'
game 'gta5'

name 'sl_sounds'
author 'SimpleLife'
version '1.0.0'
description 'Sons custom (armes…) — remplacement des wave packs vanilla (.awc).'

--[[
    Pack de REMPLACEMENT : les .awc de audiodirectory/ portent les MÊMES noms que les banques
    d'ondes vanilla (sht_pump, ptl_pistol, snp_rifle, weapons, spl_rpg_player, …). Enregistrer le
    dossier via AUDIO_WAVEPACK suffit à écraser les sons d'origine — aucun .dat54.rel nécessaire
    (on ne crée pas de nouvelles définitions de sons, on remplace l'audio de slots existants).

    Si un jour tu ajoutes des sons CUSTOM (noms inédits), il faudra alors un .dat54.rel + une ligne
    data_file 'AUDIO_SOUNDDATA' 'data/<nom>.dat54.rel'.
]]

files {
    'audiodirectory/*.awc',
}

data_file 'AUDIO_WAVEPACK' 'audiodirectory'
