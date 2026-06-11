/// Configuration ZK-AUTH - NOUVEAU FICHIER
/// Correction audit 4.3(f) : baseUrl configurable au lieu de hardcode
///
/// Emplacement : lib/config/zkauth_config.dart
library;

class ZKAuthConfig {
  /// URL de base du serveur API
  /// CORRECTION : Ne plus hardcoder '192.168.100.6'
  /// En production, utiliser HTTPS (correction 4.2.5)
  static String baseUrl = const String.fromEnvironment(
    'ZKAUTH_BASE_URL',
    defaultValue: 'http://localhost:8000',
  );

  /// Timeout de session en minutes
  /// CORRECTION audit 4.3(c) : Passe de 30 a 5 minutes pour app financiere
  static const int sessionTimeoutMinutes = 5;

  /// Nombre max de tentatives avant verrouillage
  static const int maxFailedAttempts = 5;

  /// Duree du verrouillage en secondes
  static const int lockoutDurationSeconds = 900; // 15 minutes

  /// Duree de validite du token en heures
  static const int tokenExpirationHours = 24;

  /// Nombre max d'appareils par utilisateur
  static const int maxDevices = 3;

  /// Google Drive Client ID pour le backup
  static String googleDriveClientId = const String.fromEnvironment(
    'GOOGLE_DRIVE_CLIENT_ID',
    defaultValue: '',
  );

  /// Configurer l'URL du serveur
  static void configure({
    required String serverUrl,
    String? driveClientId,
  }) {
    baseUrl = serverUrl;
    if (driveClientId != null) {
      googleDriveClientId = driveClientId;
    }
  }
}
