<p align="center">
  <img src="Design/MusicTrad-icon-1024.png" width="128" alt="Icône MusicTrad">
</p>

<h1 align="center">MusicTrad</h1>

<p align="center">
  Les paroles de la chanson qui joue dans <b>Musique</b>, traduites en français, ligne par ligne.<br>
  Petite app macOS de barre des menus, en Swift/SwiftUI, sans aucune dépendance.
</p>

---

## Ce que fait l'app

- **Détecte le morceau en cours** dans l'app Musique (titre, artiste, album, durée, position) par AppleScript, toutes les 0,5 s.
- **Récupère les paroles** sur [LRCLIB](https://lrclib.net), une API publique et gratuite, en préférant les paroles synchronisées ; si LRCLIB n'a pas de version synchronisée cohérente, l'app essaie NetEase Cloud Music.
- **Traduit en français** chaque ligne, avec la traduction affichée sous l'original, au fil de l'eau :
  - **Apple** (par défaut) : traduction sur le Mac avec le framework Translation, gratuite, hors ligne et privée ;
  - **DeepL** (option) : avec ta clé API gratuite, rangée dans le Trousseau.
- **Suit la chanson** : la ligne chantée est mise en avant et la vue défile toute seule. Un clic sur une ligne fait repartir Musique à ce passage.
- **Vérifie la synchro** : un voyant indique si le timing des paroles colle au morceau, avec un recalage en un clic sur la ligne entendue, un décalage réglable par morceau et le choix d'une autre version ou source.
- **Marque les passages instrumentaux** : ♪♪♪ qui s'allument au fil du solo, même quand le fichier de paroles ne les indique pas.
- **Prépare le morceau suivant** à l'avance (playlist en cours, ou titre suivant de l'album via l'API publique Deezer).
- **Chanson en français** : pas de traduction par défaut ; la pilule **FR → EN** la traduit en anglais à la demande (le français reste en blanc, l'anglais passe en rouge).
- Affiche la **pochette** (un clic ouvre l'album dans Musique ; grise en pause), l'**artiste** (un clic ouvre sa page dans Musique), une **étoile favori** synchronisée avec Musique, les commandes **⏮ ⏯ ⏭** et le choix de la **sortie AirPlay**.
- Garde paroles et traductions en **cache**, avec un nettoyage automatique.
- **Mode éco** (🍃 en haut à droite, actif au démarrage par défaut) : l'app reste dans la barre des menus mais ne consomme plus rien ; un bouton vert au centre la réactive. En marche, bulle fermée, elle tourne autour de 1 % de CPU.

Aucune API de paroles d'Apple n'est utilisée (il n'en existe pas pour les développeurs), ni aucun jeton privé d'Apple Music.

## Prérequis

- Mac Apple Silicon, **macOS 26 (Tahoe)** ou plus récent
- **Xcode 26** ou plus récent
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) si tu modifies `project.yml` (`brew install xcodegen`)

## Compiler et installer

```bash
git clone https://github.com/Ligrade/MusicTrad.git
cd MusicTrad
xcodegen generate   # seulement si project.yml a changé
xcodebuild -project MusicTrad.xcodeproj -scheme MusicTrad -configuration Release -derivedDataPath build build
ditto build/Build/Products/Release/MusicTrad.app /Applications/MusicTrad.app
open /Applications/MusicTrad.app
```

Tu peux aussi ouvrir `MusicTrad.xcodeproj` dans Xcode et faire **⌘R**.

L'app se loge dans la barre des menus (icône bulle de paroles) et n'apparaît pas dans le Dock.

## Autoriser l'accès à Musique

Au premier morceau joué, macOS demande : « MusicTrad souhaite contrôler Musique ». Clique sur **Autoriser**.

Si tu as refusé, ou si l'app affiche « Accès à Musique refusé » :
**Réglages Système › Confidentialité et sécurité › Automatisation › MusicTrad**, puis active **Musique**.
Le raccourci est aussi dans **Réglages de l'app › Général**.

L'app est signée « ad hoc », sans compte développeur. Après une recompilation, macOS peut redemander l'autorisation. Si l'interrupteur ne marche plus :

```bash
tccutil reset AppleEvents fr.dynamicagence.MusicTrad
```

## Réglages

| Onglet | Options |
|---|---|
| **Général** | Ouverture à la connexion, démarrage en mode éco, fenêtre flottante (désactivée par défaut, toujours au premier plan), accès à Musique |
| **Affichage** | Taille des paroles et de la traduction, paroles originales oui/non, flou des lignes inactives, aperçu, décalage de synchronisation |
| **Traduction** | Moteur Apple ou DeepL, préparation du morceau suivant, clé DeepL avec test et consommation du mois |
| **Cache** | Espace utilisé, taille maximale (50 Mo par défaut), suppression après 3 mois sans écoute, ouverture dans le Finder, vidage |

## Cache

Paroles, traductions et pochettes sont gardées dans
`~/Library/Application Support/MusicTrad/Cache`, en JSON. Chaque entrée porte sa date de création et sa date de dernière écoute.

Le cache est nettoyé au lancement puis une fois par jour :
1. suppression de ce qui n'a pas été écouté depuis la durée choisie ;
2. si la taille maximale est dépassée, suppression des titres écoutés le moins récemment ;
3. les **titres favoris** sont toujours gardés.

Une chanson pèse environ 5 Ko : 50 Mo, c'est plusieurs milliers de titres.

## Confidentialité

- Avec le moteur Apple, la traduction se fait **sur le Mac** : les paroles ne partent sur aucun serveur.
- Les seules requêtes réseau sont : LRCLIB et NetEase (paroles), Deezer et iTunes Search (morceau suivant, pochette de secours, lien vers l'album), et DeepL si tu le choisis.
- La clé DeepL est stockée dans le **Trousseau**, jamais dans le code ni dans les réglages.

## Organisation du code

```
MusicTrad/
  App/          point d'entrée, état central (AppState), réglages
  Player/       lecture de Musique (AppleScript), pochette, morceau suivant
  Lyrics/       client LRCLIB, lecture du format LRC, modèles
  Translation/  traduction Apple et DeepL, détection de langue
  Storage/      cache daté sur disque, nettoyage, Trousseau
  Views/        menu, paroles, en-tête, commandes, fenêtre flottante, réglages
Design/         icône source et script qui la dessine
project.yml     configuration XcodeGen
```

## Usage

Projet personnel, non publié sur l'App Store. Les paroles viennent de LRCLIB et ne sont pas incluses dans ce dépôt.
