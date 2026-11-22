<a id="top"></a>

<p align="center">
  <img src="Design/MusicTrad-icon-1024.png" width="128" alt="MusicTrad">
</p>

<h1 align="center">MusicTrad</h1>

<p align="center">
  <b>🇫🇷</b> Les paroles de la chanson qui joue dans Musique, traduites ligne par ligne.<br>
  <b>🇬🇧</b> The lyrics of the song playing in Apple Music, translated line by line.
</p>

<p align="center">
  <a href="https://github.com/Ligrade/MusicTrad/actions/workflows/ci.yml"><img src="https://github.com/Ligrade/MusicTrad/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <img src="https://img.shields.io/badge/version-2.0.2-blue" alt="Version 2.0.2">
  <img src="https://img.shields.io/badge/macOS-26%20Tahoe%2B-black?logo=apple" alt="macOS 26+">
  <img src="https://img.shields.io/badge/Swift-6-orange?logo=swift" alt="Swift 6">
  <img src="https://img.shields.io/badge/d%C3%A9pendances-0-brightgreen" alt="0 dependencies">
</p>

<p align="center">
  <a href="#fr"><b>🇫🇷 Français</b></a> &nbsp;·&nbsp; <a href="#en"><b>🇬🇧 English</b></a>
</p>

<!-- Captures d'écran / Screenshots : aucune dans le dépôt pour l'instant. À ajouter ici (Design/ ou docs/). -->

---

<a id="fr"></a>

# 🇫🇷 Français

<p align="right"><a href="#en">→ Switch to English</a> · <a href="#top">↑ Haut</a></p>

MusicTrad est une petite app **macOS de barre des menus**, en Swift/SwiftUI et **sans aucune dépendance**. Elle lit le morceau en cours dans l'app **Musique**, va chercher ses paroles synchronisées et les affiche avec leur **traduction en français** sous chaque ligne.

**Sommaire** : [Fonctionnalités](#fr-fonctionnalites) · [Prérequis](#fr-prerequis) · [Installation](#fr-installation) · [Utilisation](#fr-utilisation) · [Réglages et cache](#fr-reglages) · [Confidentialité](#fr-confidentialite) · [Structure](#fr-structure) · [Tests et CI](#fr-tests) · [Contribuer](#fr-contribuer) · [Licence](#fr-licence)

<a id="fr-fonctionnalites"></a>

## Fonctionnalités

| | Fonction | Détail |
|---|---|---|
| 🎵 | **Lecture suivie** | Titre, artiste, album, durée et position lus dans Musique par AppleScript : toutes les 0,5 s quand les paroles sont affichées, sinon seulement quand Musique signale un changement. |
| 📜 | **Paroles synchronisées** | [LRCLIB](https://lrclib.net) en priorité, puis NetEase Cloud Music en parallèle si LRCLIB n'a pas de version synchronisée cohérente. |
| 🌍 | **Traduction ligne par ligne** | **Apple** (par défaut, sur le Mac, gratuit, hors ligne, privé) ou **DeepL** (option, avec ta clé API rangée dans le Trousseau). |
| 🎯 | **Bonne version choisie** | Parmi plusieurs fichiers synchronisés, l'app garde celui dont le timing s'accorde avec la majorité. |
| ⏱️ | **Suivi et synchro** | La ligne chantée est mise en avant, la vue défile seule, un clic sur une ligne relance Musique à ce passage. Voyant de synchro, recalage en un clic, décalage réglable par morceau. |
| 🎼 | **Passages instrumentaux** | ♪♪♪ qui s'allument pendant les solos, même si le fichier ne les indique pas. |
| ⏭️ | **Morceau suivant préparé** | Playlist en cours, ou titre suivant de l'album via l'API publique Deezer. |
| 🖱️ | **Traduction à la demande** | Pilule **EN → FR** pour traduire ; **clic droit** pour la traduction automatique (indicateur ∞). |
| 🇫🇷 | **Chansons en français** | Pas de traduction par défaut ; un réglage permet de les traduire en anglais. |
| 🖼️ | **Pochette, favoris, commandes** | Pochette cliquable, étoile favori synchronisée avec Musique, cœur pour garder la traduction, ⏮ ⏯ ⏭, sortie AirPlay. |
| 🎨 | **Fond couleur de l'album** | Pochette floutée derrière les paroles, en fondu d'un morceau à l'autre (ou fond noir). |
| 🔽 | **Lecteur réduit** | Petit lecteur carré sous l'icône : pochette, titre, barre de lecture, commandes. Option : **pochette animée** quand l'album en a une sur Apple Music. |
| 💽 | **Sons déjà traduits** | Liste des morceaux traduits avec pochettes et recherche ; relire, écouter, garder pour toujours. |
| 🖱️ | **Clic droit sur l'icône** | **« Paroles + traduction »**, Réglages…, Quitter. |
| 🌱 | **Veille et mode éco** | Bulle fermée : lecteur après 30 min (par défaut), mode éco après 15 min sans musique ; environ 1 % de CPU en marche, quasi rien en éco. |
| 💾 | **Cache automatique** | Paroles, traductions et pochettes en JSON, nettoyage au lancement puis quotidien. |
| 👋 | **Présentation au 1ᵉʳ lancement** | Page par page, avec le choix du style (fond, pochette animée). |

Aucune API de paroles d'Apple n'est utilisée (il n'en existe pas pour les développeurs), ni aucun jeton privé d'Apple Music.

<a id="fr-prerequis"></a>

## Prérequis

- Mac Apple Silicon, **macOS 26 (Tahoe)** ou plus récent
- **Xcode 26** ou plus récent pour compiler
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) si tu modifies `project.yml` (`brew install xcodegen`)

<a id="fr-installation"></a>

## Installation

<details open>
<summary><b>Télécharger l'app</b></summary>

Télécharge le `.zip` de la dernière version sur la page [Releases](https://github.com/Ligrade/MusicTrad/releases/latest), décompresse-le et glisse **MusicTrad.app** dans **Applications**.

L'app n'est pas signée avec un certificat Apple Developer : au premier lancement, fais **clic droit › Ouvrir** (ou Réglages Système › Confidentialité et sécurité › « Ouvrir quand même »).

</details>

<details>
<summary><b>Compiler depuis les sources</b></summary>

```bash
git clone https://github.com/Ligrade/MusicTrad.git
cd MusicTrad
xcodegen generate   # seulement si project.yml a changé
xcodebuild -project MusicTrad.xcodeproj -scheme MusicTrad -configuration Release -derivedDataPath build build
ditto build/Build/Products/Release/MusicTrad.app /Applications/MusicTrad.app
open /Applications/MusicTrad.app
```

Tu peux aussi ouvrir `MusicTrad.xcodeproj` dans Xcode et faire **⌘R**.

</details>

<details>
<summary><b>Autoriser l'accès à Musique</b></summary>

Au premier morceau joué, macOS demande « MusicTrad souhaite contrôler Musique » : clique sur **Autoriser**.

Si tu as refusé, ou si l'app affiche « Accès à Musique refusé » : **Réglages Système › Confidentialité et sécurité › Automatisation › MusicTrad**, puis active **Musique** (raccourci aussi dans les Réglages de l'app › Général).

L'app est signée « ad hoc », sans compte développeur : après une recompilation, macOS peut redemander l'autorisation. Si l'interrupteur ne marche plus :

```bash
tccutil reset AppleEvents fr.dynamicagence.MusicTrad
```

</details>

<a id="fr-utilisation"></a>

## Utilisation

L'app se loge dans la barre des menus (icône bulle de paroles) et n'apparaît pas dans le Dock.

1. Lance un morceau dans **Musique**.
2. Clique sur l'icône de MusicTrad : la bulle affiche les paroles, la ligne chantée est mise en avant.
3. Clique sur la pilule **EN → FR** pour afficher la traduction (re-clic : paroles originales seules).
4. **Clic droit sur l'icône › « Paroles + traduction »** : quitte le lecteur ou le mode éco et traduit tout de suite ; si tu es déjà sur les paroles, traduit seulement.
5. Chevron ⌃ en haut à droite : replie la bulle en lecteur réduit.

<a id="fr-reglages"></a>

## Réglages et cache

<details>
<summary><b>Réglages</b></summary>

| Onglet | Options |
|---|---|
| **Général** | Ouverture à la connexion, démarrage en mode éco, lien de « Ma station », fenêtre flottante (désactivée par défaut), accès à Musique |
| **Affichage** | Fond des paroles (couleur de l'album ou noir), pochette animée, taille des paroles et de la traduction, paroles originales oui/non, flou des lignes inactives, décalage de synchronisation |
| **Traduction** | Moteur Apple ou DeepL, traduction automatique, préparation du morceau suivant, chansons en français traduites en anglais, clé DeepL avec test et consommation du mois |
| **Cache** | Espace utilisé, taille maximale (50 Mo par défaut), suppression après 2 semaines à 3 mois sans écoute (3 mois par défaut, favoris jamais supprimés), ouverture dans le Finder, vidage |

</details>

<details>
<summary><b>Cache</b></summary>

Paroles, traductions et pochettes sont dans `~/Library/Application Support/MusicTrad/Cache`, en JSON, avec date de création et de dernière écoute. Nettoyage au lancement puis une fois par jour :

1. suppression de ce qui n'a pas été écouté depuis la durée choisie ;
2. si la taille maximale est dépassée, suppression des titres écoutés le moins récemment ;
3. les **titres favoris** sont toujours gardés.

Une chanson pèse environ 5 Ko : 50 Mo, c'est plusieurs milliers de titres.

</details>

<a id="fr-confidentialite"></a>

## Confidentialité

- Avec le moteur Apple, la traduction se fait **sur le Mac** : les paroles ne partent sur aucun serveur.
- Les seules requêtes réseau : LRCLIB et NetEase (paroles), Deezer et iTunes Search (morceau suivant, pochette de secours, lien vers l'album), et DeepL si tu le choisis.
- La clé DeepL est stockée dans le **Trousseau**, jamais dans le code ni dans les réglages.

<a id="fr-structure"></a>

## Structure du projet

```
MusicTrad/
  App/          point d'entrée, état central (AppState), réglages
  Player/       lecture de Musique (AppleScript), pochette, morceau suivant, horloge
  Lyrics/       clients LRCLIB et NetEase, format LRC, modèles, stockage
  Translation/  traduction Apple et DeepL, détection de langue
  Storage/      cache daté sur disque, nettoyage, Trousseau, bibliothèque traduite
  Views/        menu, paroles, lecteur réduit, mode éco, réglages, onboarding…
MusicTradTests/ tests unitaires (Swift Testing)
Design/         icône source et script qui la dessine
project.yml     configuration XcodeGen (source de vérité du projet Xcode)
.github/        workflow CI
```

<a id="fr-tests"></a>

## Tests et CI

Les tests unitaires couvrent les parties pures : lecture du format LRC, choix de la version par consensus, règles de nettoyage du cache.

```bash
xcodegen generate
xcodebuild test -project MusicTrad.xcodeproj -scheme MusicTrad -destination 'platform=macOS'
```

La CI GitHub Actions ([ci.yml](.github/workflows/ci.yml)) compile l'app, lance les tests et vérifie que `MusicTrad.xcodeproj` est à jour par rapport à `project.yml`.

<a id="fr-contribuer"></a>

## Contribuer

1. Modifie `project.yml` (jamais le `.xcodeproj` à la main), puis lance `xcodegen generate` et commite le résultat.
2. Ajoute ou mets à jour les tests de `MusicTradTests/` quand tu touches au parsing LRC, au consensus ou au cache.
3. Vérifie que `xcodebuild test` passe avant d'ouvrir une pull request.

<a id="fr-licence"></a>

## Licence

Projet personnel, non publié sur l'App Store. Aucune licence open source n'est précisée dans ce dépôt. Les paroles viennent de LRCLIB et NetEase et ne sont pas incluses dans le dépôt.

<p align="right"><a href="#en">→ Switch to English</a> · <a href="#top">↑ Haut</a></p>

---

<a id="en"></a>

# 🇬🇧 English

<p align="right"><a href="#fr">→ Passer en français</a> · <a href="#top">↑ Top</a></p>

MusicTrad is a small **macOS menu bar app** written in Swift/SwiftUI with **zero dependencies**. It reads the track currently playing in the **Music** app, fetches its synced lyrics and shows them with a **French translation** under each line.

**Contents**: [Features](#en-features) · [Requirements](#en-requirements) · [Installation](#en-installation) · [Usage](#en-usage) · [Settings and cache](#en-settings) · [Privacy](#en-privacy) · [Project structure](#en-structure) · [Tests and CI](#en-tests) · [Contributing](#en-contributing) · [License](#en-license)

> The interface of the app is in French and translates into French.

<a id="en-features"></a>

## Features

| | Feature | Details |
|---|---|---|
| 🎵 | **Playback tracking** | Title, artist, album, duration and position read from Music via AppleScript: every 0.5 s while lyrics are shown, otherwise only when Music reports a change. |
| 📜 | **Synced lyrics** | [LRCLIB](https://lrclib.net) first, then NetEase Cloud Music in parallel if LRCLIB has no consistent synced version. |
| 🌍 | **Line-by-line translation** | **Apple** (default, on-device, free, offline, private) or **DeepL** (optional, with your API key stored in the Keychain). |
| 🎯 | **Best version picked** | Among several synced files, the app keeps the one whose timing agrees with the majority. |
| ⏱️ | **Follow and sync** | The sung line is highlighted, the view scrolls by itself, clicking a line seeks Music to that spot. Sync indicator, one-click resync, per-track adjustable offset. |
| 🎼 | **Instrumental breaks** | ♪♪♪ light up during solos, even when the file doesn't mark them. |
| ⏭️ | **Next track prefetched** | From the current playlist, or the next album track via the public Deezer API. |
| 🖱️ | **Translate on demand** | **EN → FR** pill to translate; **right-click** for automatic translation (∞ indicator). |
| 🇫🇷 | **French songs** | Not translated by default; a setting translates them into English. |
| 🖼️ | **Artwork, favorites, controls** | Clickable artwork, favorite star synced with Music, heart to keep the translation, ⏮ ⏯ ⏭, AirPlay output. |
| 🎨 | **Album color backdrop** | Blurred artwork behind the lyrics, cross-fading between tracks (or plain black). |
| 🔽 | **Mini player** | Small square player under the icon: artwork, title, seek bar, controls. Option: **animated artwork** when the album has one on Apple Music. |
| 💽 | **Already translated songs** | List of translated tracks with artwork and search; reread, play, keep forever. |
| 🖱️ | **Right-click on the icon** | **“Lyrics + translation”**, Settings…, Quit. |
| 🌱 | **Idle and eco mode** | Bubble closed: player after 30 min (default), eco mode after 15 min without music; about 1 % CPU when running, almost nothing in eco. |
| 💾 | **Automatic cache** | Lyrics, translations and artwork as JSON, cleaned at launch then daily. |
| 👋 | **First-launch tour** | Page by page, ending with the style choice (backdrop, animated artwork). |

No Apple lyrics API is used (none exists for developers), nor any private Apple Music token.

<a id="en-requirements"></a>

## Requirements

- Apple Silicon Mac running **macOS 26 (Tahoe)** or later
- **Xcode 26** or later to build
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) if you edit `project.yml` (`brew install xcodegen`)

<a id="en-installation"></a>

## Installation

<details open>
<summary><b>Download the app</b></summary>

Download the latest `.zip` from the [Releases](https://github.com/Ligrade/MusicTrad/releases/latest) page, unzip it and drag **MusicTrad.app** into **Applications**.

The app is not signed with an Apple Developer certificate: on first launch, **right-click › Open** (or System Settings › Privacy & Security › “Open Anyway”).

</details>

<details>
<summary><b>Build from source</b></summary>

```bash
git clone https://github.com/Ligrade/MusicTrad.git
cd MusicTrad
xcodegen generate   # only if project.yml changed
xcodebuild -project MusicTrad.xcodeproj -scheme MusicTrad -configuration Release -derivedDataPath build build
ditto build/Build/Products/Release/MusicTrad.app /Applications/MusicTrad.app
open /Applications/MusicTrad.app
```

You can also open `MusicTrad.xcodeproj` in Xcode and press **⌘R**.

</details>

<details>
<summary><b>Allow access to Music</b></summary>

When the first track plays, macOS asks “MusicTrad would like to control Music”: click **Allow**.

If you declined, or the app shows “Music access denied”: **System Settings › Privacy & Security › Automation › MusicTrad**, then enable **Music** (also reachable from the app's Settings › General).

The app is ad-hoc signed, with no developer account: after a rebuild, macOS may ask again. If the switch stops working:

```bash
tccutil reset AppleEvents fr.dynamicagence.MusicTrad
```

</details>

<a id="en-usage"></a>

## Usage

The app lives in the menu bar (lyrics bubble icon) and does not appear in the Dock.

1. Play a track in **Music**.
2. Click the MusicTrad icon: the bubble shows the lyrics, the sung line is highlighted.
3. Click the **EN → FR** pill to show the translation (click again: original lyrics only).
4. **Right-click the icon › “Lyrics + translation”**: leaves the player or eco mode and translates right away; if you are already on the lyrics, it only translates.
5. Chevron ⌃ at the top right: collapses the bubble into the mini player.

<a id="en-settings"></a>

## Settings and cache

<details>
<summary><b>Settings</b></summary>

| Tab | Options |
|---|---|
| **General** | Launch at login, start in eco mode, “My station” link, floating window (off by default), Music access |
| **Display** | Lyrics backdrop (blurred album color or black), animated artwork, lyrics and translation size, original lyrics on/off, blur on inactive lines, sync offset |
| **Translation** | Apple or DeepL engine, automatic translation, next-track prefetch, French songs translated into English, DeepL key with test and monthly usage |
| **Cache** | Space used, maximum size (50 MB by default), deletion after 2 weeks to 3 months without listening (3 months by default, favorites never deleted), reveal in Finder, clear |

</details>

<details>
<summary><b>Cache</b></summary>

Lyrics, translations and artwork live in `~/Library/Application Support/MusicTrad/Cache` as JSON, each with a creation date and a last-listened date. Cleaned at launch then once a day:

1. anything not listened to for the chosen duration is removed;
2. if the maximum size is exceeded, the least recently listened tracks are removed;
3. **favorite tracks** are always kept.

A song weighs about 5 KB: 50 MB holds several thousand tracks.

</details>

<a id="en-privacy"></a>

## Privacy

- With the Apple engine, translation happens **on your Mac**: lyrics are sent to no server.
- The only network requests: LRCLIB and NetEase (lyrics), Deezer and iTunes Search (next track, fallback artwork, album link), and DeepL if you choose it.
- The DeepL key is stored in the **Keychain**, never in code or settings.

<a id="en-structure"></a>

## Project structure

```
MusicTrad/
  App/          entry point, central state (AppState), settings
  Player/       Music playback (AppleScript), artwork, next track, clock
  Lyrics/       LRCLIB and NetEase clients, LRC format, models, store
  Translation/  Apple and DeepL translation, language detection
  Storage/      dated disk cache, pruning, Keychain, translated library
  Views/        menu, lyrics, mini player, eco mode, settings, onboarding…
MusicTradTests/ unit tests (Swift Testing)
Design/         source icon and the script that draws it
project.yml     XcodeGen configuration (source of truth for the Xcode project)
.github/        CI workflow
```

<a id="en-tests"></a>

## Tests and CI

Unit tests cover the pure parts: LRC parsing, consensus-based version selection, cache pruning rules.

```bash
xcodegen generate
xcodebuild test -project MusicTrad.xcodeproj -scheme MusicTrad -destination 'platform=macOS'
```

The GitHub Actions CI ([ci.yml](.github/workflows/ci.yml)) builds the app, runs the tests and checks that `MusicTrad.xcodeproj` is in sync with `project.yml`.

<a id="en-contributing"></a>

## Contributing

1. Edit `project.yml` (never the `.xcodeproj` by hand), then run `xcodegen generate` and commit the result.
2. Add or update tests in `MusicTradTests/` when touching LRC parsing, consensus or the cache.
3. Make sure `xcodebuild test` passes before opening a pull request.

<a id="en-license"></a>

## License

Personal project, not published on the App Store. No open-source license is specified in this repository. Lyrics come from LRCLIB and NetEase and are not included in the repository.

<p align="right"><a href="#fr">→ Passer en français</a> · <a href="#top">↑ Top</a></p>
