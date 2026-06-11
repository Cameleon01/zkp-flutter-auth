# 📱 Projet Flutter Complet - ZK-AUTH

Projet Flutter professionnel avec SDK réutilisable pour authentification Zero-Knowledge.

## 📦 Structure

```
flutter_final/
├── zk_auth_sdk/              #  SDK RÉUTILISABLE
│   ├── lib/
│   │   ├── api/
│   │   │   └── zk_auth_client.dart
│   │   ├── models/
│   │   │   └── models.dart
│   │   ├── utils/
│   │   │   ├── crypto_manager.dart
│   │   │   └── secure_storage_manager.dart
│   │   └── zk_auth_sdk.dart        # ⭐ Point d'entrée
│   ├── pubspec.yaml
│   └── README.md
│
└── mymomo_app/               # 📱 APPLICATION
    ├── lib/
    │   ├── screens/
    │   │   ├── splash_screen.dart
    │   │   ├── login_screen.dart
    │   │   ├── register_screen.dart
    │   │   ├── enrollment_screen.dart
    │   │   ├── home_screen.dart
    │   │   ├── backup_screen.dart
    │   │   └── restore_screen.dart
    │   └── main.dart
    ├── android/
    │   └── app/src/main/AndroidManifest.xml
    ├── ios/
    │   └── Runner/Info.plist
    └── pubspec.yaml
```

## Installation

### 1. Prérequis

```bash
flutter doctor
```

Vérifier que Flutter est installé et configuré.

### 2. Installer les dépendances

```bash
# SDK
cd zk_auth_sdk
flutter pub get

# App
cd ../mymomo_app
flutter pub get
```

### 3. Configurer le backend

Éditer `mymomo_app/lib/main.dart` ligne 14:

```dart
final zkAuthClient = ZKAuthClient(
  baseUrl: 'http://VOTRE_IP:8000', //  MODIFIER ICI
);
```

### 4. Lancer l'application

```bash
cd mymomo_app
flutter run
```

## ✨ Utilisation du SDK

### Dans l'app actuelle

Le SDK est déjà intégré via path dependency:

```dart
import 'package:zk_auth_sdk/zk_auth_sdk.dart';
import 'main.dart'; // Pour zkAuthClient

// Utilisation
await zkAuthClient.register(...);
await zkAuthClient.enroll(username);
await zkAuthClient.authenticate(username);
```

### Dans votre propre projet

1. Ajouter dans `pubspec.yaml`:

```yaml
dependencies:
  zk_auth_sdk:
    path: ../zk_auth_sdk
```

2. Utiliser:

```dart
import 'package:zk_auth_sdk/zk_auth_sdk.dart';

final zkAuth = ZKAuthClient(baseUrl: 'http://...');
await zkAuth.register(username: 'user', email: 'email', password: 'pass');
await zkAuth.enroll('user');
await zkAuth.authenticate('user');
```

##  Fonctionnalités

### Authentification
-  Inscription (username, email, phone)
-  Enrôlement ZK (génération clé privée locale)
-  Authentification biométrique locale
-  Preuves Zero-Knowledge (Schnorr)
-  Session management

### Sécurité
-  Clé privée **jamais** transmise
-  Stockage sécurisé (Keychain iOS / Keystore Android)
-  Token JWT avec expiration
-  Challenge unique par authentification

### Backup & Restore
-  Écran de sauvegarde
-  Écran de restauration (à compléter)

## 📱 Configuration Plateforme

### Android

Permissions dans `AndroidManifest.xml`:
-  INTERNET
-  USE_BIOMETRIC
-  USE_FINGERPRINT

### iOS

Face ID/Touch ID dans `Info.plist`:
-  NSFaceIDUsageDescription

## 🧪 Tests

```bash
cd mymomo_app
flutter test
```

## 🐛 Troubleshooting

### "package zk_auth_sdk not found"
```bash
cd zk_auth_sdk && flutter pub get
cd ../mymomo_app && flutter pub get
```

### "PlatformException (NotAvailable)"
Activer Touch ID/Face ID/Fingerprint dans les paramètres de l'appareil.

### "SocketException"
Vérifier que le backend est accessible:
```bash
curl http://VOTRE_IP:8000/health/
```

## 📊 Architecture

### SDK (zk_auth_sdk)

**Package Flutter réutilisable** - Peut être publié sur pub.dev

- `api/` - Client HTTP pour backend Django
- `models/` - Data models (AuthResult, UserData, KeyPair, ZKProof)
- `utils/` - Crypto (Schnorr) + Secure Storage

### App (mymomo_app)

**Application Flutter** - Utilise le SDK via dependency

- Écrans Flutter Material
- Navigation avec routes
- Gestion d'état avec StatefulWidget

## 📄 Licence

MIT

## 👨‍💻 Auteur

Clovis HOUNLELOU  
Master Sécurité Informatique - IFRI, UAC, Bénin
