# SimpleLife — Framework RP FiveM (maison)

**SimpleLife** est un framework de jeu de rôle **FiveM** développé de zéro, pensé pour être
**différent des serveurs QBCore/ESX classiques** : une architecture « lean-core » propre, une
interface **NUI « Liquid Glass »** cohérente sur tout le serveur, et des systèmes de gameplay
**sur-mesure** (téléphone device-centric, sociétés tenues par des joueurs, concessionnaire avec
import en convoi, etc.).

> ⚠️ Projet personnel / en développement. Ce dépôt contient **le code du framework** (ressources
> `sl_*`). Les dépendances tierces (ox_lib, oxmysql…) et certains assets binaires (audio, MLO) ne
> sont **pas** inclus — voir [Dépendances](#dépendances-tierces) et [Assets externes](#assets-externes-non-inclus).

---

## 💡 L'idée

Sur la plupart des serveurs FiveM, le code est fragmenté en dizaines de modules qui accèdent tous
directement à la base de données et se marchent dessus (races, bugs de scope, ordre de chargement…).
SimpleLife part d'un principe inverse :

> **Une seule ressource autoritaire (`sl_core`)** détient tout ce qui est difficile à faire
> correctement — base de données, migrations, registre des joueurs, économie, bus d'événements,
> interactions. **Les fonctionnalités sont des plugins « bêtes »** qui parlent à `sl_core` via des
> `exports` — jamais d'accès direct à MariaDB, jamais de global partagé entre ressources.

À cela s'ajoute une exigence de **finition** : chaque interface passe par un même design system
**Liquid Glass** (verre translucide, sans `backdrop-filter` car le CEF ne peut pas flouter le jeu),
et chaque système est conçu pour être **serveur-autoritaire** (l'argent, le stock, les clés… sont
résolus et validés côté serveur, jamais confiés au client).

---

## 🧱 Principes / philosophie

- **Lean-core** : `sl_core` = autorité unique (DB/migrations/joueurs/éco/bus). Le reste = plugins.
- **Serveur-autoritaire** : prix, stock, argent, permissions, clés → décidés et vérifiés serveur.
- **Exports en syntaxe colon** : `exports.sl_core:getChar(src)` (le wrapper CFX consomme `self`).
- **NUI Liquid Glass** : un helper `glass(accent)` produit tout le style à partir d'une couleur.
- **Bespoke, pas générique** : les systèmes sont cadrés par de gros QCM avec le porteur du projet
  avant d'être développés (ex. le module véhicules).
- **Anti-triche par design** : opérations d'argent atomiques + rollback, décréments de stock
  *race-safe* (`UPDATE … WHERE qty >= ?`), verrou single-flight par joueur, plafond de privilèges.

---

## 🛠️ Stack technique

| Élément | Détail |
|---|---|
| Serveur | FiveM (artifact ≥ 23683), `sv_enforceGameBuild 3751`, **OneSync ON** |
| Langage | **Lua 5.4** (serveur/client) |
| Base de données | **MariaDB** via **oxmysql** (pool de connexions ; seul `sl_core` l'appelle) |
| Interfaces (NUI) | **React 19 · Vite · Tailwind v4 · Zustand** (surfaces propres par ressource) |
| Utilitaires | **ox_lib** (menus/dialogs/progress/skillcheck), **ox_target** (interactions) |

---

## 🏗️ Architecture

```
                ┌─────────────────────────────────────────────┐
                │                  sl_core                     │
                │  DB · migrations · registre joueurs · éco    │
                │  bus d'events · service registry · monde     │
                └───────────────▲───────────────▲─────────────┘
                                │ exports (colon) │ bus / services
        ┌───────────┬───────────┼───────────┬────┴──────┬───────────┐
        │           │           │           │           │           │
     sl_ui     sl_interact  sl_inventory  sl_bank    sl_phone   sl_identity
        │                                                            
   design system   ox_target      poids/grille    ATM     device-centric   comptes+arrivée
   Liquid Glass    wrapper                                   
        │
   ┌────┴─────────────┬────────────────┬─────────────┬───────────────┐
 sl_shops         sl_vehicles        sl_hud       sl_minimap       sl_admin
 boutiques+LTD    concession+convoi  jauges       minimap propre   menu F10
```

Chaque ressource déclare `dependency 'sl_core'` (le core démarre en premier). Les migrations DB
sont triées **topologiquement** (header `-- requires:`) et appliquées **une seule fois** au boot.

---

## 📦 Les ressources

| Ressource | Rôle |
|---|---|
| **sl_core** | Autorité : DB, migrations, registre joueurs, économie (cash/banque), bus d'événements, service registry, contrôle du monde. Toutes les features en dépendent. |
| **sl_ui** | Design system NUI **Liquid Glass** (menus clavier, notifs, input, inventaire). Helper `glass(accentHex)`. |
| **sl_interact** | Wrapper **ox_target** (œil + touche) : `addModel/addCoords/addEntity/addLocalEntity`, nettoyage par ressource. |
| **sl_identity** | Comptes, multi-perso, création + **customisation** (fivem-appearance), **arrivée en avion** (vol enregistré puis rejoué), spawn + persistance de position. |
| **sl_bank** | Distributeurs (ATM) : solde / dépôt / retrait, menu Liquid Glass. |
| **sl_inventory** | Inventaire **au poids** (grille drag & drop), slots d'équipement, sacs au sol, items *usables* (bus `item:used`). Exports `addItem/removeItem/hasItem/…`. |
| **sl_phone** | **Téléphone device-centric** (NUI React/Zustand propre) : Contacts, Messages, Appels (pma-voice), Banque, Crypto, Caméra, Galerie, Réglages, **iFruit Store** (installer/désinstaller des apps), **Société**, **Véhicules/Clés**, **Annuaire**. Données liées à l'appareil (uuid). |
| **sl_shops** | Boutiques **24/7** (PNJ, argent = puits) + **sociétés LTD** tenues par des joueurs : grades & permissions custom, caisse, **POS** (un employé facture le client), grossiste. Points caisse/stock/gestion séparés. |
| **sl_vehicles** | **Concessionnaire tenu par des joueurs** + **import en convoi** (commande → port → flatbed/porte-voitures → stock), **parking physique persistant**, **clés virtuelles liées au téléphone** (moteur bloqué sans clé), vol/hotwire, fourrière, carburant, reprise, transfert entre joueurs. |
| **sl_hud** | Jauges vie / armure / **faim** / **soif** (SVG Liquid Glass) ; besoins persistés dans `sl_core`. |
| **sl_minimap** | Minimap « propre » : retire les barres vie/armure natives + le réticule rouge (scaleforms streamés — *assets non inclus*). |
| **sl_admin** | Menu **admin F10** (ACE `sl.admin`, re-check serveur sur chaque action) : argent, armes, véhicules, items, joueurs, self, noclip + **Dev/Test** (boutiques, concessions, crypto…). |
| **sl_sounds** | Pack de **remplacement de sons** (armes) via `AUDIO_WAVEPACK` (*assets `.awc` non inclus*). |

---

## 🔌 Dépendances tierces

À installer séparément dans le `resources/` de ton serveur (non fournies ici) :

| Ressource | Rôle |
|---|---|
| **oxmysql** | Connecteur MariaDB (pool). |
| **ox_lib** (≥ 3.33) | Menus, dialogues, progress, skill-check, callbacks, propriétés véhicule. |
| **ox_target** | Interactions (base de `sl_interact`). |
| **fivem-appearance** | Créateur de personnage (utilisé par `sl_identity`). |
| **pma-voice** | Voix de proximité 3D + appels du téléphone. |
| **screenshot-basic** | Capture d'écran (caméra du téléphone). |

Optionnel : **bob74_ipl** (gestion des IPL/intérieurs), une **MLO concessionnaire** pour l'intérieur.

---

## 🚀 Installation

1. **Prérequis** : serveur FiveM (build 3751, OneSync ON), **MariaDB**, Node.js + npm (pour builder les NUI).
2. **Copier les ressources** : place `resources/[simplelife]` et `resources/[audio]` dans le
   `resources/` de ton serveur, et installe les [dépendances tierces](#dépendances-tierces).
3. **Base de données** : crée la base
   ```sql
   CREATE DATABASE simplelife_dev CHARACTER SET utf8mb4;
   ```
   Les tables sont créées automatiquement par les migrations de `sl_core` au premier boot.
4. **server.cfg** : pars de [`server.cfg.example`](server.cfg.example) — renseigne `sv_licenseKey`,
   `mysql_connection_string` et tes identifiants admin, et **garde l'ordre des `ensure`**.
5. **Build des interfaces** (voir ci-dessous) — le `html/` compilé est déjà committé, à rebuilder
   seulement si tu modifies une UI.
6. Lance le serveur et rejoins.

---

## 🎨 Build des interfaces NUI

Les ressources avec une UI React sont : **sl_ui**, **sl_phone**, **sl_shops**, **sl_vehicles**.
Pour chacune :

```bash
cd "resources/[simplelife]/sl_vehicles/web"
npm install
npm run build          # sortie → ../html (base './', servi par ui_page)
```

Puis `restart <ressource>` en jeu (et reconnexion pour les assets streamés).

---

## 🚧 Assets externes non inclus

Pour éviter de redistribuer des assets tiers / Rockstar, ces fichiers binaires sont **exclus** du
dépôt (voir `.gitignore`). Les ressources concernées restent fournies, il suffit d'ajouter les assets :

- **sl_sounds** → dépose ton pack de sons `.awc` dans `resources/[audio]/sl_sounds/audiodirectory/`.
- **sl_minimap** → dépose les scaleforms `.gfx` (pack *b2k-minimap*) dans `resources/[simplelife]/sl_minimap/stream/`.
- **MLO concessionnaire** → une MLO d'intérieur est optionnelle (le système fonctionne aussi sur le
  bâtiment vanilla). Ajoute-la comme ressource séparée si tu veux un showroom custom.

---

## 🗄️ Base de données

MariaDB, migrations dans `resources/[simplelife]/sl_core/migrations/` (`001` → `014`), appliquées
automatiquement et **dans l'ordre des dépendances** (header `-- requires:` en tête de chaque `.sql`),
avec un ledger (`sl_migrations`) et un verrou anti-double-apply. Tables principales : `accounts`,
`characters`, `phones` (+ comms/média/éco), `shops`/`shop_*`, `vehicles`/`vehicle_keys`,
`dealerships`/`dealership_*`, `stashes`, etc.

---

## 🧑‍💻 Développement

- **Modif Lua** → `restart <ressource>` en console.
- **Modif NUI** → `npm run build` dans le `web/` de la ressource, puis `restart`.
- **Migration** → ajouter `0NN_*.sql` + l'inscrire dans `sl_core/migrations/manifest.lua` → `restart sl_core`.
- **Outils dev/test** (donner argent/items/véhicules, assigner une société…) → dans le **menu F10 Admin**, pas en commandes chat.
- Doc d'architecture détaillée (classes de bugs neutralisées, conventions) : voir [`PROJECT.md`](PROJECT.md).

---

## 📜 Crédits & licence

Framework **SimpleLife** — projet personnel. Le code des ressources `sl_*` est l'œuvre de l'auteur.
Les dépendances tierces (ox_lib, oxmysql, ox_target, fivem-appearance, pma-voice…) et tout asset
ajouté (audio, MLO, minimap) restent soumis à **leurs licences respectives**.

© SimpleLife — tous droits réservés (usage à définir par l'auteur).
