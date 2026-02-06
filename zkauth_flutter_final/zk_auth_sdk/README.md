#  ZK-AUTH SDK

SDK Flutter réutilisable pour authentification Zero-Knowledge avec protocole Schnorr.

## Installation

Dans votre `pubspec.yaml`:

```yaml
dependencies:
  zk_auth_sdk:
    path: ../zk_auth_sdk
```

Ou depuis Git:

```yaml
dependencies:
  zk_auth_sdk:
    git:
      url: https://github.com/votre-repo/zk_auth_sdk.git
```

## Usage

```dart
import 'package:zk_auth_sdk/zk_auth_sdk.dart';

// Initialisation
final zkAuth = ZKAuthClient(
  baseUrl: 'https://your-backend.com',
);

// Inscription
final regResult = await zkAuth.register(
  username: 'johndoe',
  email: 'john@example.com',
  password: 'secure123',
);

// Enrôlement (génère clé privée locale)
final enrollResult = await zkAuth.enroll('johndoe');

// Authentification
final authResult = await zkAuth.authenticate('johndoe');
if (authResult.success) {
  print('Token: ${authResult.accessToken}');
  // Navigation vers HomeScreen
}

// Vérifier session
final isValid = await zkAuth.isSessionValid();

// Déconnexion
await zkAuth.logout();
```

## API

### ZKAuthClient

#### Méthodes principales

- `register({username, email, password})` - Inscription
- `enroll(username)` - Enrôlement ZK
- `authenticate(username)` - Connexion
- `logout()` - Déconnexion
- `isSessionValid()` - Vérifier session
- `revokeDevice(username)` - Révoquer appareil

## Architecture

```
zk_auth_sdk/
├── lib/
│   ├── api/
│   │   └── zk_auth_client.dart    # Client HTTP
│   ├── models/
│   │   └── models.dart             # Data models
│   ├── utils/
│   │   ├── crypto_manager.dart     # Schnorr crypto
│   │   └── secure_storage_manager.dart
│   └── zk_auth_sdk.dart           # Export principal
└── pubspec.yaml
```

## Sécurité

- ✅ Clé privée **jamais** transmise
- ✅ Stockage sécurisé (Keychain/Keystore)
- ✅ Zero-Knowledge Proofs (Schnorr)
- ✅ Challenge unique par auth
- ✅ Token JWT avec expiration

## Licence

MIT
