/// ZK-AUTH SDK - Zero-Knowledge Authentication for Flutter
///
/// Implémente le protocole de Schnorr sur secp256k1
/// Compatible avec backend Django REST API
///
/// VERSION CORRIGÉE AUDIT - Ajout FragmentManager
library zk_auth_sdk;

// API Client
export 'api/zk_auth_client.dart';

// Models
export 'models/models.dart';

// Utils (optionnel - pour usage avancé)
export 'utils/crypto_manager.dart';
export 'utils/secure_storage_manager.dart';
export 'utils/fragment_manager.dart'; // NOUVEAU : fragmentation XOR + AES-256-GCM
export 'utils/zk_logger.dart';
