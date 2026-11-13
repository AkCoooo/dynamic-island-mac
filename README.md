<p align="center">
  <img src="docs/icon.png" width="160" height="160" alt="Icône de Dynamic Island Mac">
</p>

<h1 align="center">Dynamic Island Mac</h1>

<p align="center">
  <strong>Ton encoche prend vie.</strong><br>
  Ta musique, tes paroles, tes copies, tes fichiers et ton agenda dans une île qui s'ouvre au survol,<br>
  et un lecteur en verre jusque sur l'écran verrouillé.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-14%2B-2A1A5E?style=flat-square&logo=apple&logoColor=white" alt="macOS 14 ou plus">
  <img src="https://img.shields.io/badge/Swift-5.10-8C45D9?style=flat-square&logo=swift&logoColor=white" alt="Swift 5.10">
  <img src="https://img.shields.io/badge/SwiftUI-natif-F96B85?style=flat-square" alt="SwiftUI natif">
</p>

<p align="center">
  <a href="#installer"><strong>Installer</strong></a>
  &nbsp;·&nbsp;
  <a href="#ce-que-fait-lîle">Voir ce qu'elle fait</a>
  &nbsp;·&nbsp;
  <a href="#les-réglages">Les réglages</a>
</p>

<p align="center">
  <img src="docs/screens/lecture.png" width="720" alt="L'île ouverte sur le morceau en cours">
</p>

---

## Ce que fait l'île

- **Elle s'ouvre au survol.** Passe la souris sur l'encoche : l'île se déplie avec un ressort et se replie quand tu t'éloignes. Pas d'encoche ? Elle dessine la sienne.
- **Elle joue ta musique.** Spotify et Musique : pochette, titre, barre de lecture que tu peux faire glisser, aléatoire, répétition, et le choix de la sortie audio (haut-parleurs, AirPods, écran, AirPlay).
- **Elle chante avec toi.** Les paroles synchronisées défilent sous le titre et se remplissent au fil du chant.
- **Elle se souvient de tes copies.** Les 30 derniers textes, liens et images copiés, à recopier d'un clic. Un raccourci (⇧⌘V par défaut, à choisir dans les réglages) ouvre l'historique près du pointeur, dans n'importe quelle app. En mémoire seulement, et jamais les mots de passe venus d'un gestionnaire de mots de passe.
- **Elle garde tes fichiers.** Dépose un fichier sur l'île : il attend sur l'étagère jusqu'à ce que tu le glisses ailleurs ou l'envoies par AirDrop.
- **Elle connaît ta journée.** Prochains rendez-vous, météo, minuteur et chrono, toujours à portée de souris.
- **Elle te prévient.** Chargeur branché, batterie faible, AirPods connectés, volume, fin du minuteur : l'île s'élargit un instant, puis se fait oublier.

<p align="center">
  <img src="docs/screens/reduite.png" width="600" alt="L'île réduite pendant la lecture"><br>
  <img src="docs/screens/charge.png" width="600" alt="Notification de charge">
</p>

| Presse-papiers | Étagère |
|---|---|
| <img src="docs/screens/presse-papiers.png" alt="Onglet Presse-papiers"> | <img src="docs/screens/etagere.png" alt="Onglet Étagère"> |
| **Agenda** | **Minuteur et chrono** |
| <img src="docs/screens/agenda.png" alt="Onglet Agenda"> | <img src="docs/screens/minuteur.png" alt="Onglet Minuteur"> |
| **Apparence Clair** | |
| <img src="docs/screens/clair.png" alt="L'île ouverte en apparence Clair"> | |

## Sur l'écran verrouillé

Verrouille ton Mac (⌃⌘Q) pendant que la musique joue, ou même en pause : la pochette remplit tout l'écran, nette au centre et floutée vers les bords. Par-dessus, l'heure en grand, la météo, la batterie, la pochette et un petit lecteur en verre pour piloter la musique sans déverrouiller.

<p align="center">
  <img src="docs/screens/ecran-verrouille.jpg" width="720" alt="L'écran verrouillé avec la pochette en fond">
</p>

Deux styles plus sobres existent, « Grande pochette » et « Carte », qui gardent le fond d'écran de macOS. Le mot de passe et Touch ID marchent toujours : le fond laisse passer les clics, et une option garde le champ du mot de passe visible.

> [!NOTE]
> L'écran verrouillé passe par une API privée de macOS. Elle peut cesser de fonctionner après une mise à jour du système : l'option se désactive dans les réglages.

## Installer

Il faut macOS 14 ou plus récent et les outils de ligne de commande d'Xcode (`xcode-select --install`).

```bash
git clone https://github.com/AkCoooo/dynamic-island-mac.git
cd dynamic-island-mac
./scripts/install.sh
```

Le script compile, emballe `Dynamic Island Mac.app` avec son icône, la signe, l'installe dans `~/Applications` et la lance. Tu la retrouves ensuite dans le Launchpad et dans Spotlight, comme n'importe quelle app.

Au premier lancement, les réglages s'ouvrent pour te montrer où tout se trouve.

## Les réglages

<img src="docs/screens/reglages.png" width="360" align="right" alt="Fenêtre de réglages">

Trois chemins y mènent :

- **Relance l'app** depuis le Launchpad, Spotlight ou le dossier Applications.
- **Clique sur ⚙** en haut à droite de l'île ouverte.
- **Clique sur le logo de l'île** dans la barre des menus, puis sur **Réglages…** Tu peux masquer ce logo dans les réglages : les deux autres chemins suffisent.

Tu y choisis l'apparence (Noir, Verre ou Clair : l'île ouverte, les menus et les réglages suivent), le délai d'ouverture, les notifications, les options de l'écran verrouillé, les coins arrondis en bas de l'écran, la ville pour la météo et le lancement à l'ouverture de session.

<br clear="right">

## Autorisations

macOS te les demande une fois, au moment où l'app en a besoin :

| Autorisation | Pourquoi |
|---|---|
| **Automatisation** (Spotify, Musique) | Lire le morceau en cours et piloter la lecture |
| **Bluetooth** | Voir quand tes écouteurs se connectent |
| **Calendriers** | Afficher tes prochains rendez-vous |
| **Position** | La météo de là où tu es (inutile si tu saisis une ville) |

Ni l'Accessibilité, ni l'enregistrement de l'écran ne sont nécessaires.

## Ce qu'elle ne fait pas (encore)

- **La batterie des AirPods** n'a pas d'API publique : l'île l'affiche quand macOS la fournit, sinon elle écrit « Connecté ».
- **Les autres lecteurs** (navigateurs, Tidal…) ne sont pas suivis : macOS réserve cette information aux apps d'Apple.
- **Le HUD de volume de macOS** reste affiché en plus de celui de l'île.

## Sous le capot

| Fichier | Rôle |
|---|---|
| `NotchWindowController.swift` | La vitre transparente posée sur l'encoche, et le survol |
| `NotchView.swift` | La forme de l'île, ses onglets et toutes ses vues |
| `NotchModel.swift` | L'état partagé : mode, taille, morceau, minuteur, étagère |
| `NowPlayingService.swift` | Spotify et Musique, pochettes, commandes |
| `ClipboardMonitor.swift`, `ClipboardPopup.swift`, `HotKey.swift` | L'historique du presse-papiers, sa fenêtre et son raccourci |
| `LyricsService.swift` | Les paroles synchronisées, depuis [LRCLIB](https://lrclib.net) |
| `LockScreen.swift` | Le fond, l'heure, les widgets et le lecteur de l'écran verrouillé |
| `AudioOutputs.swift`, `VolumeMonitor.swift` | Sorties audio et volume (Core Audio) |
| `SystemMonitors.swift` | Batterie et écouteurs Bluetooth |
| `AgendaWeather.swift` | Agenda (EventKit) et météo ([Open-Meteo](https://open-meteo.com)) |
| `Settings.swift` | Les réglages et leur fenêtre |
| `CornerOverlay.swift`, `KeepAwake.swift` | Coins arrondis, écran gardé allumé |
| `Snapshot.swift` | Rendu des écrans en PNG, pour vérifier le design sans écran |

Pour régénérer les captures : `swift build && .build/debug/DynamicIslandMac --snapshot /tmp/captures`.
