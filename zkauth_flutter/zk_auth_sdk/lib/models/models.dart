/// Résultat d'un Enrollement ZK-AUTH
class EnrollmentResult {
  final bool success;
  final String? message;
  final String? publicKey;
  final String? error;

  EnrollmentResult({
    required this.success,
    this.message,
    this.publicKey,
    this.error,
  });

  factory EnrollmentResult.success({
    required String publicKey,
    String? message,
  }) {
    return EnrollmentResult(
      success: true,
      publicKey: publicKey,
      message: message ?? 'Enrollement réuussi',
    );
  }

  factory EnrollmentResult.failure({
    required String error,
  }) {
    return EnrollmentResult(
      success: false,
      error: error,
      message: 'Echec de l\'Enrollement',
    );
  }
}

/// Résultat d'une authentification
class AuthResult {
  final bool success;
  final String? message;
  final String? accessToken;
  final String? refreshToken;
  final UserData? user;
  final String? error;

  AuthResult({
    required this.success,
    this.message,
    this.accessToken,
    this.refreshToken,
    this.user,
    this.error,
  });

  factory AuthResult.success({
    required String accessToken,
    required UserData user,
    String? refreshToken,
    String? message,
  }) {
    return AuthResult(
      success: true,
      accessToken: accessToken,
      refreshToken: refreshToken,
      user: user,
      message: message ?? 'Authentification réussie',
    );
  }

  factory AuthResult.failure({
    required String error,
  }) {
    return AuthResult(
      success: false,
      error: error,
      message: 'Echec de l\'authentification',
    );
  }
}

/// Données utilisateur
class UserData {
  final int id;
  final String username;
  final String email;
  final bool isEnrolled;

  UserData({
    required this.id,
    required this.username,
    required this.email,
    required this.isEnrolled,
  });

  factory UserData.fromJson(Map<String, dynamic> json) {
    return UserData(
      id: json['id'] as int,
      username: json['username'] as String,
      email: json['email'] as String,
      isEnrolled: json['is_enrolled'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'username': username,
      'email': email,
      'is_enrolled': isEnrolled,
    };
  }
}

/// Paire de Clés
class KeyPair {
  final String privateKey;
  final String publicKey;

  KeyPair({
    required this.privateKey,
    required this.publicKey,
  });
}

/// Preuve Zero-Knowledge (Schnorr)
class ZKProof {
  final String r; // Commitment
  final String s; // Response
  final String challenge; // Challenge

  ZKProof({
    required this.r,
    required this.s,
    required this.challenge,
  });

  Map<String, dynamic> toJson() {
    return {
      'r': r,
      's': s,
      'challenge': challenge,
    };
  }
}

/// Résultat de sauvegarde
class BackupResult {
  final bool success;
  final String? message;
  final String? driveFileId;
  final String? error;

  BackupResult({
    required this.success,
    this.message,
    this.driveFileId,
    this.error,
  });

  factory BackupResult.success({
    required String driveFileId,
    String? message,
  }) {
    return BackupResult(
      success: true,
      driveFileId: driveFileId,
      message: message ?? 'Sauvegarde réussie',
    );
  }

  factory BackupResult.failure({required String error}) {
    return BackupResult(
      success: false,
      error: error,
    );
  }
}

/// Type de sécurité disponible sur l'appareil
enum SecurityType {
  none, // Aucune sécurité
  pin, // PIN/mot de passe
  fingerprint, // Empreinte digitale
  face, // Reconnaissance faciale
  iris, // Reconnaissance iris
}

/// Statut de sécurité de l'appareil
class SecurityStatus {
  final bool isAvailable;
  final SecurityType type;
  final String message;

  SecurityStatus({
    required this.isAvailable,
    required this.type,
    required this.message,
  });

  @override
  String toString() {
    return 'SecurityStatus(available: $isAvailable, type: $type, message: $message)';
  }
}
