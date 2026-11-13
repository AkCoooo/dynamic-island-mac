# Dynamic Island Mac

Une île dynamique pour l'encoche du Mac, écrite en Swift/SwiftUI.

## Installer

Prérequis : macOS 14 ou plus récent, et les Command Line Tools (`xcode-select --install`). Xcode n'est pas nécessaire.

```bash
./scripts/install.sh
```

Le script compile l'app, la copie dans `/Applications/Dynamic Island Mac.app` et la lance. Relancez-le après chaque modification du code.

Pour seulement compiler sans installer :

```bash
./scripts/build-app.sh
open "build/Dynamic Island Mac.app"
```

Dynamic Island Mac n'a pas d'icône dans le Dock. Tout passe par l'icône en forme de capsule dans la barre des menus : **Réglages…**, **Aperçu de l'écran verrouillé** et **Quitter**.

## Fonctions

### L'île

- **Ouverture au survol** de l'encoche, avec une animation à ressort. Sans encoche, Dynamic Island Mac dessine sa propre île.
- **Onglets** dans l'île ouverte :
  - **Lecture** : pochette, titre, artiste, ligne de paroles, barre de progression déplaçable, commandes.
  - **Paroles** : défilement synchronisé. Un clic sur une ligne saute à ce moment du morceau.
  - **Étagère** : déposez des fichiers sur l'île, puis glissez-les ailleurs, envoyez-les par AirDrop ou ouvrez-les d'un double-clic.
  - **Agenda** : les prochains événements d'aujourd'hui et de demain.
  - **Minuteur et chrono** : le décompte reste visible dans l'île réduite.
- **Île réduite** : pochette et égaliseur pendant la lecture. Elle reste affichée en pause et ne se replie que lorsqu'aucun morceau n'est chargé.
- **Notifications** : chargeur branché, batterie faible, écouteurs Bluetooth, volume, fin du minuteur.
- **Météo** (Open-Meteo) et **batterie** dans la bande du haut.

### L'écran verrouillé

Quand l'écran est verrouillé, Dynamic Island Mac affiche au centre une rangée de widgets (météo, batterie, prochain rendez-vous) et un lecteur en verre avec les commandes. Une option affiche aussi une grande pochette. L'horloge système et le champ de mot de passe ne sont pas recouverts.

Cette fonction s'appuie sur une API privée de macOS (SkyLight). Elle ne fait qu'afficher : le déverrouillage reste entièrement géré par macOS. Elle peut cesser de fonctionner après une mise à jour du système.

### Autres

- Coins du bas de l'écran arrondis (option).
- Retour haptique sur le trackpad.
- Lancement à l'ouverture de session.
- Thème « Noir » ou « Verre » pour l'île ouverte.

## Permissions demandées par macOS

| Permission | Pourquoi |
|---|---|
| Automatisation (Spotify, Musique) | Lire la position et la pochette, piloter la lecture |
| Bluetooth | Détecter la connexion des écouteurs |
| Calendriers | Afficher les prochains événements |
| Position | Météo locale (inutile si une ville est saisie dans les réglages) |

Dynamic Island Mac n'a besoin ni de l'Accessibilité ni de l'enregistrement d'écran.

## Limites connues

- **Batterie des AirPods** : aucune API publique ne la fournit. Dynamic Island Mac l'affiche seulement si IOBluetooth l'expose, sinon il écrit « Connecté ».
- **Autres lecteurs** (navigateurs, Tidal…) : pas pris en charge. MediaRemote est réservé aux apps Apple depuis macOS 15.4.
- **HUD de volume** : celui de macOS reste affiché en plus de celui de Dynamic Island Mac. Le masquer demanderait d'intercepter les touches (permission Accessibilité).
- **Luminosité** : pas d'API publique pour la lire, donc pas de HUD de luminosité.
- **Distribution** : signature ad hoc, pour un usage local. Pour distribuer l'app, il faut une signature Developer ID et une notarisation.

## Vérifier le design sans écran

```bash
swift build
.build/debug/DynamicIslandMac --snapshot /tmp/dynamic-island-snaps
```

Cette commande rend chaque état de l'île et de l'écran verrouillé en PNG, avec des données fictives. `open "build/Dynamic Island Mac.app" --args --preview-expanded` garde l'île ouverte en permanence.

## Structure

| Fichier | Rôle |
|---|---|
| `AppDelegate.swift` | Démarrage, menu de la barre des menus |
| `NotchWindowController.swift` | Panneau transparent, positionnement sur l'encoche, survol |
| `NotchView.swift` | Forme de l'île, onglets et toutes les vues de l'île |
| `NotchModel.swift` | État partagé, modes, tailles, minuteur, étagère |
| `Settings.swift` | Réglages persistants, fenêtre de réglages, haptique |
| `NowPlayingService.swift` | Spotify et Musique (notifications + AppleScript), pochettes |
| `LyricsService.swift` | Paroles LRCLIB et lecture du format LRC |
| `SystemMonitors.swift` | Batterie (IOKit) et écouteurs (IOBluetooth) |
| `VolumeMonitor.swift` | Volume de la sortie audio (Core Audio) |
| `AgendaWeather.swift` | Agenda (EventKit) et météo (Open-Meteo) |
| `LockScreen.swift` | Widgets et lecteur sur l'écran verrouillé |
| `CornerOverlay.swift` | Coins arrondis en bas de l'écran |
| `Snapshot.swift` | Rendu PNG des états pour vérifier le design |
