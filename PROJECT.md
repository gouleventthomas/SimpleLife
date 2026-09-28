# SimpleLife — Documentation projet

> **But de ce fichier** : référence complète et auto-suffisante de TOUT ce qui a été
> construit, choisi, configuré. Sert à retrouver le contexte après un compactage.
> Tenu à jour au fil de l'avancement. Dernière grosse étape : intégration de la
> customisation de perso (fivem-appearance) dans le flux d'arrivée.

---

## 1. Vue d'ensemble

- **Projet** : SimpleLife — framework RP FiveM **maison**, reconstruit de zéro le **2026-06-21** (l'ancien build de 30 modules `sl-*` a été supprimé ; backup ZIP dans `E:\Projets\SimpleLife_backup_20260621_204306.zip`).
- **Racine serveur** : `E:\Projets\txData\FiveMBasicServerCFXDefault_03197F.base\`
- **Modules SimpleLife** : `resources\[local]\[simplelife]\` (chaque module = un dossier `sl_*`, underscore).
- **Déps tierces** : `resources\` (hors `[simplelife]`).
- **Build FiveM** : `sv_enforceGameBuild 3751` (mp2025_02). **Lua 5.4**. UI = **NUI** (HTML/CSS/JS).

### Outils / environnement machine
| Outil | Détail |
|---|---|
| **MariaDB 12.2** | local `localhost:3306` ; bases `simplelife_dev` / `simplelife_prod` ; user `simplelife` / mdp `simplelife_local` ; binaire `C:\Program Files\MariaDB 12.2\bin\mysql.exe` |
| **Node.js** | v24 + **npm 11** (yarn ABSENT → toujours utiliser **npm**) |
| **git** | présent |
| **Lua CLI** | ABSENT (pas de luac → la syntaxe Lua est validée au boot FiveM) |

> ⚠️ **Chemins à crochets** (`[local]`, `[simplelife]`) : en PowerShell utiliser `-LiteralPath` (sinon `[ ]` = wildcards). `New-Item` n'a pas `-LiteralPath` en PS 5.1 → créer un dossier à crochets via `[System.IO.Directory]::CreateDirectory($p)`. Vite/npm gèrent bien les crochets (testé).

---

## 2. Dépendances tierces (dans `resources\`)

| Resource | Rôle | Notes |
|---|---|---|
| **oxmysql** | Connecteur MariaDB | v2.14.1. Pool de connexions (important pour B1c). Seul `sl_core` l'appelle. |
| **ox_lib** | Lib UI/util | v3.33.0. Dispo pour menus/dialogs/notifs/etc. |
| **ox_target** | Interactions (œil + touche) | **Choisi** mais **pas encore branché** (futur `sl_interact`). |
| **fivem-appearance** | Créateur de perso (visage/cheveux/vêtements/props) | `pedr0fontoura`, MIT, standalone. **Cloné + buildé** (voir §10). Utilisé via exports seulement. |

---

## 3. Architecture « lean-core » + décisions figées

**Principe** : UNE ressource autoritaire `sl_core` détient tout ce qui est dur à faire correctement (DB, migrations, registre joueurs, bus, service registry, interaction, économie). Les features sont des **plugins bêtes** qui parlent à `sl_core` via exports/bus/services — jamais d'accès direct à MariaDB, jamais de global partagé, jamais de scope Lua d'une autre ressource.

### Les 9 ressources prévues
| Resource | Rôle | État |
|---|---|---|
| **sl_core** | DB, migrations, joueurs, bus, économie, registry, interaction | ✅ **fait** (Phase 0) |
| **sl_ui** | TOUT le NUI (React/Vite/Tailwind/ShadCN) : HUD, écrans, notifs | ✅ base faite |
| **sl_interact** | Visée œil + E (via ox_target) | ⏳ pas commencé |
| **sl_identity** | Comptes, multichar, création+customisation, spawn, arrivée avion | 🚧 en cours |
| **sl_jobs** | Jobs/grades/paie + skills/XP + crafting + **police/EMS/mort-revive** | ⏳ |
| **sl_vehicles** | Concession/garage/clés/fuel | ⏳ |
| **sl_world** | Propriétés/shops/events + **crime/gangs** | ⏳ |
| **sl_phone** | Apps iOS-dark (promu depuis sl_ui plus tard) | ⏳ |
| **sl_voice** | Voix proximité (Mumble) | ⏳ |

### Décisions figées (par le user)
- **Nommage underscore** : `sl_core`, `sl_ui`… (pas `sl-core`).
- **Pas de `sl_safety`** : police/EMS/mort → dans `sl_jobs` ; crime/gangs → dans `sl_world`.
- **NUI** : React + Vite + Tailwind + **ShadCN** (radix/nova), thème grunge GTA-V à terme.
- **Interactions** : ox_target (œil + touche), pas de système maison.
- **Customisation perso** : fivem-appearance.
- **Arrivée** : nouveau perso arrive **en avion** à LSIA (vol **enregistré puis rejoué**, voir §9) ; perso existant = reprise à la dernière position.

---

## 4. Base de données

Migrations gérées par `sl_core` (runner unique, voir §6). Tables actuelles dans `simplelife_dev` :

| Table | Colonnes clés |
|---|---|
| `accounts` | `license` PK, `created`, `last_seen` |
| `characters` | `id` PK, `license` FK→accounts, `firstname`, `lastname`, `dob`, `model`, **`appearance` JSON**, `cash` (def 500), `bank` (def 5000), `position` JSON, `metadata` JSON, `deleted_at`, `created` |
| `sl_migrations` | ledger des migrations (`id` PK, `name`, `checksum`, `applied_at`) |
| `sl_migrate_lock` | verrou claim-row anti-double-apply (`id` PK, `holder`, `expires_at`) |

**Reset DB** (dev) :
```
& 'C:\Program Files\MariaDB 12.2\bin\mysql.exe' -u simplelife -psimplelife_local -e "DROP DATABASE simplelife_dev; CREATE DATABASE simplelife_dev CHARACTER SET utf8mb4;"
```

---

## 5. Les 6 classes de bugs de l'ancien build — neutralisées par design

| # | Bug | Solution dans sl_core |
|---|---|---|
| **B1** | Race migration (double-apply → crash) | runner appelé **1 seul endroit** (onResourceStart de sl_core) + latch + ledger + **claim-row lock `sl_migrate_lock`** (PK, survit au pool oxmysql — `GET_LOCK` était mort-né car session-scoped) |
| **B2** | Ordre FK (errno 150) | migrations triées **topologiquement** via header `-- requires:`, keyées par filename |
| **B3** | Scope cross-fichier (nil deref) | pas de `local SL = exports[...]` caché ; `SLCore` global resource-shared + `use()` ; cross-resource = `exports.sl_core:fn()` en **syntaxe colon** (le wrapper CFX consomme `self`) |
| **B4** | Clés JSON (array 0-indexé) | UN seul `Codec.encodeJson` (sentinelles `__jsontype` réelles, pas `json.array` qui n'existe pas) ; rejet des maps numériques |
| **B5** | Split SQL sur `;` | tokenizer comment/string-aware ; `;` dans commentaires OK |
| **B6** | Fragmentation (30 modules) | 9 ressources groupées par état partagé ; `dependency 'sl_core'` force le core en premier |

---

## 6. `sl_core` (fondation)

**Fichiers** : `shared/{config,codec}.lua` · `server/{_bootstrap,db,sql,migrate,registry,bus,players,economy,interact,commands,boot}.lua` · `client/core.lua` · `migrations/{001_accounts,002_characters,003_appearance}.sql` + `manifest.lua`.

**Conventions clés** :
- Modules : `SLCore.module('name', tbl)` / `SLCore.use('name')` / `SLCore.require('name')` (même état Lua dans la ressource).
- DB : seul `server/db.lua` appelle `MySQL.*` (oxmysql 2.14.1). API : `MySQL.query/single/scalar/insert/update/transaction.await`.
- JSON : toujours `Codec.encodeJson/decodeJson`.
- Boot : `server/boot.lua` (charge en dernier) attend oxmysql, lance les migrations **une fois**, set `GlobalState.slCoreReady=true` + `GlobalState.slCoreEnv='dev'`, print banner `[sl_core] migrations: N applied / M present | ready (env=dev)`.

**Exports cross-resource** (colon) : `isReady`, `getChar(src)`, `getCharByCharId`, `loadCharacter(src,charId)`, `addMoney/removeMoney/transfer`, `saveChar`, **`saveAppearance(charId, appearance)`**, `dbQuery/dbSingle/dbScalar/dbInsert/dbUpdate/dbTransaction`, `registerInteraction`, `use`, `call`/`provide` (service registry), `on`/`emit` (bus), `status`.

`loadCharacter` renvoie un char `{ charId, license, firstname, lastname, model, dob, cash, bank, coords, metadata, appearance }` (`appearance` = nil si jamais customisé).

**Commandes** : `/sl info | status | modules | db ping | db status | db migrations | save` (ACE group.admin).

---

## 7. `sl_ui` (NUI unique)

**Stack** : React 19 · Vite 8 · TypeScript · **Tailwind v4** · **ShadCN** (radix/nova) · alias `@`. Source dans `sl_ui/web/`, build → `sl_ui/html/` (servi par `ui_page`).

**Build NUI** :
```
cd "...\sl_ui\web" ; npm run build   # → ../html (base './' = chemins relatifs obligatoires en NUI)
```
puis `restart sl_ui` en jeu.

**Pont Lua** (`client/bridge.lua`) — le SEUL à toucher `SendNUIMessage`/`SetNuiFocus`. Exports pour les features :
| Export | Effet |
|---|---|
| `exports.sl_ui:open(screen, payload)` | ouvre un écran (prend le focus NUI) |
| `exports.sl_ui:close()` | ferme + rend le focus |
| `exports.sl_ui:notify(kind, msg)` | toast |
| `exports.sl_ui:hud(data)` | pousse les valeurs HUD |

**Protocole NUI** :
- Lua→React : `SendNUIMessage({action, data})`. Actions : `open {screen,payload}`, `closeAll`, `hudUpdate`, `notify {kind,message}`.
- React→Lua : `fetchNui('dispatch', {event, data})` → le pont ré-émet `TriggerEvent('sl_ui:nui', event, data)` (générique, les features écoutent). Aussi `fetchNui('uiReady')` au montage (**handshake** : le pont met en file les messages envoyés trop tôt et les rejoue — sinon le 1er `open` est perdu).
- Helpers React : `web/src/lib/fetchNui.ts`, `web/src/hooks/useNuiEvent.ts`.

**Écrans** : `App.tsx` (routeur + HUD), `screens/CharSelect.tsx`, `screens/CharCreate.tsx`, `components/Toast.tsx`.

---

## 8. `sl_identity` (identité + arrivée)

**Fichiers** : `shared/config.lua` · `server/{arrival,main,commands}.lua` · `client/{main,arrival,recorder}.lua` · `recordings/arrival_last.json` (enregistrement de vol) · `fxmanifest.lua` (déclare `files { 'recordings/*.json' }`).

### Flux complet
```
Connexion → écran NOIR tenu (jamais le flash spawn GTA)
  → spawn forcé via spawnmanager au HoldCoord (autospawn OFF)
  → clientReady → openEntry :
       • a des persos  → écran SELECT  → choix → RESUME (dernière position)
       • aucun perso   → écran CREATE  → form (nom/date/genre)
                          → CRÉATEUR fivem-appearance (voir §10)
                          → appearance sauvée → ARRIVÉE EN AVION (voir §9) → tarmac
```

**Fiabilité (#1)** : un nouveau joueur ne doit JAMAIS softlock. Latches `arrivalActive` / `customizeActive` mettent le thread « hold » en veille pendant la cinématique/créateur ; `releaseToPlayer()` est le point de sortie garanti (visible + contrôlable + fade-in). Chaque attente est bornée (timeout + fallback).

**Spawn bootstrap** (car `basic-gamemode` désactivé → rien ne spawn) : `exports.spawnmanager:setAutoSpawn(false)` + `spawnPlayer` au HoldCoord.

### Config (`shared/config.lua`) — placeholders à calibrer avec `/here`
| Clé | Rôle |
|---|---|
| `CharacterCap` | 3 persos / compte |
| `Models` | `{m='mp_m_freemode_01', f='mp_f_freemode_01'}` |
| `HoldCoord` | coord cachée (ciel) où le ped est tenu avant spawn |
| `CustomizeCoord` | où se tient le ped pendant le créateur (placeholder aéroport) |
| `DisembarkPoint` / `FallbackSpawn` | où on finit après l'avion / reprise sans coords |
| `PlaneModel` | `jet` (le `jumbo` ne se charge PAS) |
| `Landing` | géométrie de piste (legacy IA — l'arrivée utilise maintenant le **replay**) |
| `Replay.speed` | vitesse de relecture du vol enregistré (1.0 = fidèle) |
| `Timeouts` | model/collision/land/disembark/session/core |
| `Camera` | offset caméra chase |

---

## 9. Système d'arrivée en avion (enregistrement → replay)

**Pourquoi** : l'IA (`TaskPlaneLand`) faisait des pivots moches ; le lerp scripté était robotique. Solution : **on pilote un vrai vol à la main, on l'enregistre, on le rejoue** image par image (organique + reproductible).

**Enregistrer** (`client/recorder.lua`, dev) :
- `/startrecarrivage` → spawn un `jet` 300m au-dessus de toi (tu pilotes) + capture position+rotation 20 Hz + indicateur `● REC`.
- `/stoprecarrivage` → envoie les frames au serveur qui écrit `recordings/arrival_last.json`.

**Rejouer** (`server/arrival.lua` + `client/arrival.lua`) :
- Le **serveur** lit `arrival_last.json` (`Arrival.loadFrames()`), downsample ~500 frames en arrays compacts `[t,x,y,z,pitch,roll,yaw]`, et les envoie dans le payload `sl_identity:arrival` (le **client ne peut PAS** lire un fichier resource arbitraire → c'est pour ça qu'on passe par le serveur).
- Le client rejoue : avion gelé, `SetEntityCoordsNoOffset` + `SetEntityRotation` interpolés par timestamp, joueur passager.
- Fin → **débarquement visible** (`TaskLeaveVehicle`) puis contrôle rendu.
- **Re-enregistrer ne nécessite PAS de restart** (le serveur relit le fichier à chaque `/arrival`).

---

## 10. Customisation perso (fivem-appearance)

**Install** : cloné dans `resources\fivem-appearance` puis buildé avec **npm** (yarn absent) :
```
cd "...\fivem-appearance\game" ; npm install ; npm run build        # → game/dist/index.js (esbuild)
cd "...\fivem-appearance\web"  ; npm install ; npx vite build        # → web/dist/ (tsc échoue sur vieux types → vite direct)
```
`ensure fivem-appearance` dans server.cfg (avant sl_core).

**Exports utilisés** (colon) :
- `startPlayerCustomization(cb, config)` — ouvre le créateur (gère caméra/NUI/ped lui-même via les coords courantes du ped) ; `cb(appearance)` au save, `cb(nil)` au cancel. `config = {ped,headBlend,faceFeatures,headOverlays,components,props,tattoos,allowExit}` (booléens). On passe `allowExit=false` à la création.
- `setPlayerAppearance(appearance)` — applique le look **+ le modèle** (donc NE PAS faire `applyModel` en plus quand on a une appearance).
- `getPedAppearance(ped)`.

**Intégration** : création → `sl_identity:customize` (client : ferme sl_ui, applique modèle freemode, TP au CustomizeCoord, ouvre le créateur) → save → `sl_identity:appearanceSaved` (serveur : `sl_core:saveAppearance` puis `Arrival.begin`). Au spawn (resume + arrivée) : si `appearance` → `setPlayerAppearance` sinon `applyModel`. → **persiste à travers les reconnexions** (ré-appliqué à chaque spawn).

---

## 11. Commandes dev (env=dev uniquement)

| Commande | Ressource | Effet |
|---|---|---|
| `/sl info\|status\|modules\|db ...` | sl_core | diagnostic core + migrations |
| `/arrival` | sl_identity | rejoue la cinématique d'arrivée (avion) |
| `/charcreate` `/charselect` | sl_identity | ré-ouvre les écrans création/sélection |
| `/resume` | sl_identity | rejoue la reprise au dernier point |
| `/customize` | sl_identity | ré-ouvre le créateur fivem-appearance (déclenche une arrivée après) |
| `/here` | sl_identity | affiche `vector3(...) heading=...` (calibrage des coords) |
| `/startrecarrivage` `/stoprecarrivage` | sl_identity | enregistre / sauve un vol d'arrivée |

---

## 12. Workflows de dev

- **Modif Lua** : éditer → `restart <resource>` en console.
- **Modif NUI (React)** : éditer `sl_ui/web/src` → `cd sl_ui/web ; npm run build` → `restart sl_ui`.
- **Nouveau fichier dans une ressource** : `restart <resource>` (un fichier neuf n'est chargé qu'au restart). Pour le NUI, penser aussi à `files{}` si le client doit lire un fichier (sinon passer par le serveur).
- **Migration DB** : ajouter `00X_*.sql` + l'ajouter à `sl_core/migrations/manifest.lua` → `restart sl_core` (idempotent via `IF NOT EXISTS` + ledger).
- **Restart complet** : txAdmin → Restart (à faire si plusieurs ressources / une migration / une nouvelle dépendance changent).
- **Suggestions chat** : `TriggerEvent('chat:addSuggestion', '/cmd', 'desc')` (sinon la commande marche mais n'apparaît pas dans l'autocomplétion).

---

## 13. `server.cfg` — ordre des `ensure`

```
ensure mapmanager / chat / spawnmanager / sessionmanager / hardcap   # base FiveM (basic-gamemode DÉSACTIVÉ)
ensure oxmysql
ensure ox_lib
ensure fivem-appearance
ensure sl_core
ensure sl_ui
ensure sl_identity
```
`mysql_connection_string` → `simplelife_dev`. Identifiants admin (JackLania) : license `0ba5eaa6d1cdaeab1aeda87fb991461ad259f7ff`, fivem `84633`, discord `306118713537462273`.

---

## 14. État d'avancement / roadmap

- ✅ **Phase 0** — `sl_core` (fondation, 6 bugs neutralisés, boot déterministe).
- 🚧 **Phase 1** — boucle jouable :
  - ✅ `sl_ui` (HUD, écrans, pont NUI).
  - 🚧 `sl_identity` : flux connexion/création/sélection/spawn ✅ ; **arrivée avion (replay)** ✅ ; **customisation (fivem-appearance)** ✅ (à tester).
  - ⏳ **Navette bus** aéroport (descendre de l'avion → bus → dépose hors piste → forçage descente) — *tâche planifiée*.
  - ⏳ **Vol partagé (1b)** : file d'attente ~2 min, tous les nouveaux dans le MÊME avion réseau, arrivée simultanée.
- ⏳ **Phase 2** — RP cœur : `sl_jobs`, `sl_vehicles`, `sl_world`.
- ⏳ **Phase 3** — breadth : `sl_phone`, `sl_voice`, monde.

---

## 15. Journal des décisions (pourquoi)

- **Repartir de zéro** (vs réparer l'ancien) : trop de fragmentation (30 modules) + bugs récurrents.
- **lean-core** : choisi via atelier multi-agents (top des juges unicité + complétude RP).
- **fivem-appearance vs illenium** : fivem-appearance car standalone/custom-framework, on possède la persistance dans sl_core. illenium = couplé QB/ESX/ox.
- **Replay de vol vs IA/lerp** : un humain pilote = atterrissage organique exact, sans la physique IA capricieuse.
- **Serveur lit le recording** (vs client `files{}`) : `LoadResourceFile` client ne lit que les fichiers streamés ; le serveur lit tout → fiable + pas de restart au re-record.
- **Déploiement** : tout en **local dev** ; pas de prod sans accord explicite.
