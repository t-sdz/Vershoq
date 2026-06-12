# Vershoq 📸

Application mobile Flutter de photos spontanées — inspirée de BeReal. Une notification aléatoire t'invite à photographier quelqu'un de ton groupe ; la photo apparaît instantanément dans le fil partagé.

---

## Fonctionnalités

- **Notifications aléatoires** : reçois une alerte à une heure imprévisible avec le prénom d'un membre de ton groupe
- **Compte à rebours** : tu as quelques secondes pour capturer la photo après avoir ouvert l'app
- **Galerie de groupe** : toutes les photos du groupe s'affichent dans un fil vertical (style TikTok) en temps réel
- **Gestion de groupe** : crée un groupe avec un code, partage-le à tes amis, ou rejoins-en un
- **Administration** : l'admin peut supprimer des membres du groupe
- **Téléchargement** : sauvegarde n'importe quelle photo dans ta galerie locale
- **Authentification** : connexion par email/mot de passe via Firebase Auth
- **Paramètres personnalisables** :
  - Heures limites pour les notifications (ex. pas de notif après 22h)
  - Nombre minimum et maximum de notifications par jour
  - Liste des prénoms utilisés dans les notifications

---

## Architecture

```
lib/
├── main.dart                  # Point d'entrée, routing auth
├── firebase_options.dart      # Config Firebase (ignoré par git)
├── theme/
│   └── v_theme.dart           # Design system solaire (couleurs, gradients, widgets)
├── models/
│   ├── photo_entry.dart       # Photo locale
│   ├── group.dart             # Groupe + membre
│   └── group_photo_entry.dart # Photo partagée (base64)
├── services/
│   ├── auth_service.dart      # Firebase Auth wrapper
│   ├── group_service.dart     # Firestore : groupes & membres
│   ├── group_photo_service.dart # Firestore : galerie partagée
│   ├── notification_service.dart # Notifications locales planifiées
│   ├── names_service.dart     # Liste de prénoms
│   └── storage_service.dart   # Photos locales (SharedPreferences)
└── screens/
    ├── auth_screen.dart        # Login / inscription
    ├── landing_screen.dart     # Accueil après connexion
    ├── feed_screen.dart        # Fil principal (PageView vertical)
    ├── camera_screen.dart      # Capture photo avec countdown
    ├── result_screen.dart      # Confirmation post-capture
    ├── groups_screen.dart      # Gestion du groupe
    ├── create_group_screen.dart
    ├── join_group_screen.dart
    ├── settings_screen.dart    # Paramètres notifications
    └── gallery_screen.dart     # Galerie locale
```

---

## Stack technique

| Technologie | Usage |
|---|---|
| Flutter 3.44 / Dart 3.8 | Framework mobile |
| Firebase Auth | Authentification email/password |
| Cloud Firestore | Base de données temps réel (groupes, photos) |
| `flutter_local_notifications` | Notifications locales planifiées |
| `camera` + CameraX | Capture photo (front / back) |
| `flutter_image_compress` | Compression avant upload (~50 KB) |
| `image` | Flip horizontal caméra frontale |
| `gal` | Sauvegarde en galerie native |
| `shared_preferences` | Persistence locale (groupe actif, settings) |

> **Note** : les photos sont stockées en base64 dans Firestore (pas de Firebase Storage) pour rester sur le plan Spark gratuit.

---

## Installation

### Prérequis

- Flutter SDK ≥ 3.10
- Android SDK (API 21+) ou Xcode 15+
- Un projet Firebase avec Firestore et Authentication activés

### Étapes

```bash
# 1. Cloner le repo
git clone https://github.com/t-sdz/vershoq.git
cd vershoq

# 2. Installer les dépendances
flutter pub get

# 3. Ajouter les fichiers de config Firebase (non versionnés)
# Android : android/app/google-services.json
# iOS     : ios/Runner/GoogleService-Info.plist
# Dart    : lib/firebase_options.dart
# → générer avec : flutterfire configure

# 4. Lancer l'app
flutter run
```

### Build APK (Android)

```bash
flutter build apk --release
# Résultat : build/app/outputs/flutter-apk/app-release.apk
```

---

## Configuration Firebase

1. Créer un projet sur [console.firebase.google.com](https://console.firebase.google.com)
2. Activer **Authentication → Email/Password**
3. Activer **Cloud Firestore** en mode production
4. Déployer les règles de sécurité (`firestore.rules`) depuis la console Firebase

### Règles Firestore

Les règles (`firestore.rules`) garantissent :
- Lecture/écriture uniquement aux utilisateurs connectés
- Chaque utilisateur ne peut écrire que sous son propre UID
- Seul l'admin du groupe peut supprimer des membres
- Seul l'uploader peut supprimer sa propre photo

---

## Sécurité

- Authentification obligatoire pour toutes les opérations Firestore
- Les règles Firestore vérifient `request.auth.uid` côté serveur
- Les fichiers de configuration Firebase (`google-services.json`, `firebase_options.dart`) sont exclus du dépôt git via `.gitignore`

---

## Captures d'écran

> *À ajouter : écran d'accueil, fil de photos, paramètres*

---

## Licence

Projet personnel — tous droits réservés.
