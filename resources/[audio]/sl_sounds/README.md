# sl_sounds — sons custom (armes…)

Pack de **remplacement** de wave packs audio. Les `.awc` de `audiodirectory/` portent les mêmes
noms que les banques vanilla (`sht_pump`, `ptl_pistol`, `weapons`, `spl_rpg_player`, …), donc le
jeu remplace simplement les sons d'origine.

- `audiodirectory/` → les `.awc` (déjà en place, enregistrés via `AUDIO_WAVEPACK`)
- `data/` → vide (un `.dat54.rel` ne serait nécessaire QUE pour des sons **inédits**, pas pour des remplacements)

## Appliquer
1. `ensure sl_sounds` est dans `server.cfg`.
2. **Restart serveur + reconnexion** (l'audio se met en cache au join).

## Note
Le dossier contient aussi des banques **non-armes** (ambience, weather, vehicles, frontend, doors,
feet_*, animals_footsteps, collision(s), movement, player_switch, low_latency…). Elles remplaceront
AUSSI ces sons vanilla. Si tu ne veux QUE les armes, supprime ces `.awc`.
