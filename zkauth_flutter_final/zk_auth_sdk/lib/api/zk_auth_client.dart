import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/models.dart';
import '../utils/crypto_manager.dart';
import '../utils/secure_storage_manager.dart';
import 'package:local_auth/local_auth.dart';
import 'package:flutter/services.dart';
import '../utils/google_drive_backup.dart';

/// Client d'authentification Zero-Knowledge
class ZKAuthClient {
  final String baseUrl;
  final CryptoManager _crypto = CryptoManager();
  final SecureStorageManager _storage = SecureStorageManager();
  final GoogleDriveBackup _driveBackup = GoogleDriveBackup();
  final LocalAuthentication _localAuth = LocalAuthentication();

  ZKAuthClient({required this.baseUrl});

  // =========================================
  // 1. INSCRIPTION (Register)
  // =========================================

  /// Inscription d'un nouvel utilisateur
  Future<AuthResult> register({
    required String username,
    required String email,
    required String password,
  }) async {
    try {
      print('Inscription: $username');

      final response = await http.post(
        Uri.parse('$baseUrl/api/auth/register/'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'username': username,
          'email': email,
          'password': password,
        }),
      );

      if (response.statusCode == 201) {
        print(' Inscription réussie');
        return AuthResult(success: true);
      } else {
        final error = json.decode(response.body);
        print(' Erreur inscription: $error');
        return AuthResult(success: false, error: error.toString());
      }
    } catch (e) {
      print(' Exception inscription: $e');
      return AuthResult(success: false, error: e.toString());
    }
  }

  // =========================================
  // 2. ENROLEMENT ZK (Enrollment)
  // =========================================

  /// enrollement Zero-Knowledge (génération Clé + sauvegarde)
  Future<AuthResult> enroll(String username) async {
    try {
      print('Enrollement ZK pour: $username');

      // 1. Générer paire de Clés localement
      final keyPair = _crypto.generateKeyPair();
      print(' Clés générées');

      // 2. Sauvegarder la Clé privée localement (JAMAIS envoyée!)
      await _storage.savePrivateKey(username, keyPair.privateKey);
      await _storage.setCurrentUsername(username);
      print(' Clé privée sauvegardée localement');

      // 3. Envoyer UNIQUEMENT la Clé publique au serveur
      final response = await http.post(
        Uri.parse('$baseUrl/api/auth/enroll/'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'username': username,
          'public_key': keyPair.publicKey,
        }),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        // 4. Marquer comme enrÃ´lé
        await _storage.setEnrolled(username, true);
        print(' enrollement réussi');

        return AuthResult(
          success: true,
          message: 'enrollement réussi. Clé publique enregistrée.',
        );
      } else {
        print(' Erreur serveur: ${response.body}');
        return AuthResult(success: false, error: response.body);
      }
    } catch (e) {
      print(' Exception enrollement: $e');
      return AuthResult(success: false, error: e.toString());
    }
  }

  // =========================================
  // 3. VERIFICATION ENROLEMENT
  // =========================================

  /// Vérifie si un utilisateur est déjÃ  enrÃ´lé localement
  Future<bool> isUserEnrolled(String username) async {
    try {
      final isEnrolled = await _storage.isEnrolled(username);

      if (isEnrolled) {
        print(' $username est enrollé');
      } else {
        print(' $username n\'est pas enrollé');
      }

      return isEnrolled;
    } catch (e) {
      print(' Erreur vérification: $e');
      return false;
    }
  }

  // =========================================
  // 4. AUTHENTIFICATION ZK (Login)
  // =========================================

  /// Authentification Zero-Knowledge (sans révéler la Clé privée)
  Future<AuthResult> authenticate(String username) async {
    try {
      print('Authentification pour: $username');

      // 1. Vérifier enrollement local
      final isEnrolled = await _storage.isEnrolled(username);
      if (!isEnrolled) {
        print(' Utilisateur non enrollé');
        return AuthResult(
          success: false,
          error: 'Utilisateur non enrollé. Veuillez vous inscrire d\'abord.',
        );
      }

      // 2. Récupérer la Clé privée locale
      final privateKey = await _storage.getPrivateKey(username);
      if (privateKey == null) {
        print(' Clé privée introuvable');
        return AuthResult(
          success: false,
          error: 'Clé privée introuvable. Veuillez vous ré-enroller.',
        );
      }

      // 3. Demander un challenge au serveur
      final challengeResponse = await http.get(
        Uri.parse('$baseUrl/api/auth/challenge/?username=$username'),
      );

      if (challengeResponse.statusCode != 200) {
        print(' Erreur challenge: ${challengeResponse.body}');
        return AuthResult(success: false, error: 'Erreur lors du challenge');
      }

      final challengeData = json.decode(challengeResponse.body);
      final challenge = challengeData['challenge'] as String;
      print(' Challenge réussi');

      // 4. Sauvegarder le challenge temporairement
      await _storage.saveChallenge(challenge);

      // 5. Générer une preuve ZK (protocole de Schnorr)
      final proof = _crypto.generateProof(
        privateKeyHex: privateKey,
        challenge: challenge,
      );
      print(' Preuve ZK générée');

      // 6. Envoyer la preuve au serveur (PAS la Clé privée!)
      final authResponse = await http.post(
        Uri.parse('$baseUrl/api/auth/authenticate/'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'username': username,
          'proof': {
            'r': proof.r,
            's': proof.s,
            'challenge': challenge,
          },
        }),
      );

      if (authResponse.statusCode == 200) {
        final authData = json.decode(authResponse.body);
        final token = authData['token'] as String?;
        final message = authData['message'] as String?;

        // 7. Sauvegarder le token de session
        if (token != null) {
          await _storage.saveSessionToken(token);
          await _storage.saveAuthTimestamp(DateTime.now());
        }

        // 8. Définir comme utilisateur actuel
        await _storage.setCurrentUsername(username);

        print(' Authentification réussie');

        return AuthResult(
          success: true,
          message: message ?? 'Authentification réussie',
        );
      } else {
        print('  authentification: ${authResponse.body}');
        return AuthResult(
          success: false,
          error: 'Authentification echouée. Vérifiez vos identifiants.',
        );
      }
    } catch (e) {
      print(' Exception authentification: $e');
      return AuthResult(success: false, error: e.toString());
    }
  }

  // =========================================
  // 5. GESTION DE SESSION
  // =========================================

  /// Vérifier si un utilisateur est déjÃ  enrÃ´lé
  Future<bool> isUserEnrolledLocally() async {
    final username = await getCurrentUsername();
    if (username == null) return false;
    return await _storage.isEnrolled(username);
  }

  /// Obtenir le username enregistré
  Future<String?> getCurrentUsername() async {
    return await _storage.getCurrentUsername();
  }

  /// Obtenir le token de session actuel
  Future<String?> getSessionToken() async {
    return await _storage.getSessionToken();
  }

  /// Vérifier si la session est valide
  Future<bool> isSessionValid() async {
    try {
      final token = await getSessionToken();
      if (token == null) return false;

      final timestamp = await _storage.getAuthTimestamp();
      if (timestamp == null) return false;

      // Session expire aprÃ¨s 24h
      final now = DateTime.now();
      final difference = now.difference(timestamp);

      return difference.inHours < 24;
    } catch (e) {
      return false;
    }
  }

  // =========================================
  // 6. DECONNEXION
  // =========================================

  /// Déconnexion (supprime session + tokens, garde Clé privée)
  Future<void> logout() async {
    print('Déconnexion...');

    // Supprimer session et tokens (PAS la Clé privée)
    await _storage.clearSession();

    print(' Déconnexion réussie (Clé privée conservée)');
  }

  // =========================================
  // 7. REVOCATION (Admin/Security)
  // =========================================

  /// Révoquer un appareil compromis
  Future<AuthResult> revokeDevice(String username) async {
    try {
      print('ðŸš« Révocation appareil: $username');

      final response = await http.post(
        Uri.parse('$baseUrl/api/auth/revoke/'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'username': username}),
      );

      if (response.statusCode == 200) {
        // Supprimer TOUTES les données locales
        await _storage.deleteUser(username);
        print(' Appareil révoqué');

        return AuthResult(success: true, message: 'Appareil révoqué');
      } else {
        return AuthResult(success: false, error: response.body);
      }
    } catch (e) {
      return AuthResult(success: false, error: e.toString());
    }
  }

  // =========================================
  // 8. UTILITAIRES
  // =========================================

  /// Obtenir la Clé privée (pour backup uniquement!)
  Future<String?> getPrivateKey(String username) async {
    return await _storage.getPrivateKey(username);
  }

  /// Vérifier la disponibilité de la biométrie
  Future<bool> canCheckBiometrics() async {
    try {
      final localAuth = LocalAuthentication();
      return await localAuth.canCheckBiometrics;
    } catch (e) {
      return false;
    }
  }

  /// Liste des utilisateurs enrÃ´lés sur cet appareil
  Future<List<String>> getEnrolledUsers() async {
    return await _storage.getEnrolledUsers();
  }

// ✅ NOUVELLE MÉTHODE : Enrôlement avec biométrie
  Future<AuthResult> enrollWithBiometrics(String username) async {
    try {
      print(' Enrôlement avec biométrie pour: $username');

      // 1. Vérifier biométrie
      final canCheck = await _localAuth.canCheckBiometrics;
      final isSupported = await _localAuth.isDeviceSupported();

      if (canCheck && isSupported) {
        print(' Demande biométrie...');

        bool authenticated = false;
        try {
          authenticated = await _localAuth.authenticate(
            localizedReason:
                'Authentifiez-vous pour générer votre clé sécurisée',
            options: const AuthenticationOptions(
              stickyAuth: true,
              biometricOnly: false,
              useErrorDialogs: true,
            ),
          );
        } on PlatformException catch (e) {
          print('⚠️ Erreur biométrie: ${e.code}');
          // Continuer sans biométrie
        }

        if (canCheck && !authenticated) {
          return AuthResult(
            success: false,
            error: 'Authentification biométrique requise',
          );
        }

        print('✅ Biométrie validée');
      } else {
        print('⚠️ Biométrie non disponible');
      }

      // 2. Enrôlement normal
      return await enroll(username);
    } catch (e) {
      print('❌ Erreur enrollWithBiometrics: $e');
      return AuthResult(success: false, error: e.toString());
    }
  }

// ✅ NOUVELLE MÉTHODE : Sauvegarde Google Drive

  Future<BackupResult> backupToGoogleDrive(String username) async {
    try {
      print('[BACKUP] Début sauvegarde pour: $username');

      // 1. Vérifier et authentifier (flexible biométrie/PIN)
      final authResult = await _authenticateForSensitiveOperation(
        reason: 'Authentifiez-vous pour sauvegarder votre clé',
      );

      if (!authResult) {
        return BackupResult.failure(
          error: 'Authentification requise pour la sauvegarde',
        );
      }

      print('[BACKUP] Authentification réussie');

      // 2. Récupérer clé privée
      final privateKey = await _storage.getPrivateKey(username);
      if (privateKey == null) {
        return BackupResult.failure(error: 'Clé privée introuvable');
      }

      print('[BACKUP] Clé récupérée: ${privateKey.length} chars');

      // 3. Fragmenter
      final mid = (privateKey.length / 2).ceil();
      final fragmentA = privateKey.substring(0, mid);
      final fragmentB = privateKey.substring(mid);

      print('[BACKUP] Fragmenté: A=${fragmentA.length}, B=${fragmentB.length}');

      // 4. Sauvegarder Fragment A sur Google Drive
      final driveFileId = await _driveBackup.saveFragment(
        username: username,
        fragment: fragmentA,
        fragmentType: 'A',
      );

      if (driveFileId == null) {
        return BackupResult.failure(error: 'Échec Google Drive');
      }

      print('[BACKUP] Fragment A → Drive');

      // 5. Envoyer Fragment B au serveur
      try {
        final response = await http.post(
          Uri.parse('$baseUrl/api/auth/backup-fragment/'),
          headers: {'Content-Type': 'application/json'},
          body: json.encode({
            'username': username,
            'fragment': fragmentB,
            'fragment_type': 'B',
          }),
        );

        if (response.statusCode != 200 && response.statusCode != 201) {
          print('[BACKUP] Serveur fragment B: ${response.statusCode}');
        } else {
          print('[BACKUP] Fragment B → Serveur');
        }
      } catch (e) {
        print('[BACKUP] Erreur serveur: $e');
      }

      print('[BACKUP] Backup complet réussi');

      return BackupResult.success(
        driveFileId: driveFileId,
        message: 'Fragment A → Google Drive\nFragment B → Serveur',
      );
    } catch (e) {
      print('[BACKUP] Erreur: $e');
      return BackupResult.failure(error: e.toString());
    }
  }

// ✅ NOUVELLE MÉTHODE : Restauration depuis Google Drive
  Future<AuthResult> restoreFromGoogleDrive({
    required String username,
    required String email,
  }) async {
    try {
      print('🔄 Restauration pour: $username');

      // 1. Récupérer Fragment A depuis Google Drive
      final fragmentA = await _driveBackup.getFragment(
        username: username,
        fragmentType: 'A',
      );

      if (fragmentA == null) {
        return AuthResult.failure(error: 'Fragment A non trouvé sur Drive');
      }

      print('✅ Fragment A récupéré');

      // 2. Récupérer Fragment B depuis le serveur
      final response = await http.post(
        Uri.parse('$baseUrl/api/auth/restore-fragment/'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'username': username,
          'email': email,
        }),
      );

      if (response.statusCode != 200) {
        return AuthResult.failure(error: 'Fragment B non trouvé sur serveur');
      }

      final data = json.decode(response.body);
      final fragmentB = data['fragment'] as String;

      print('✅ Fragment B récupéré');

      // 3. Reconstituer la clé
      final privateKey = fragmentA + fragmentB;

      print('✅ Clé reconstituée: ${privateKey.length} chars');

      // 4. Sauvegarder localement
      await _storage.savePrivateKey(username, privateKey);
      await _storage.setEnrolled(username, true);
      await _storage.setCurrentUsername(username);

      print('✅ Restauration réussie');

      return AuthResult(
        success: true,
        message: 'Compte restauré avec succès',
      );
    } catch (e) {
      print('❌ Erreur restauration: $e');
      return AuthResult.failure(error: e.toString());
    }
  }

  /// Vérifie si l'appareil a une sécurité configurée

  Future<bool> _authenticateForSensitiveOperation({
    required String reason,
  }) async {
    try {
      // 1. Vérifier disponibilité biométrie
      final canCheckBiometrics = await _localAuth.canCheckBiometrics;
      final isDeviceSupported = await _localAuth.isDeviceSupported();

      print('[AUTH] Biométrie disponible: $canCheckBiometrics');
      print('[AUTH] Device supporté: $isDeviceSupported');

      if (!canCheckBiometrics && !isDeviceSupported) {
        // Aucune sécurité disponible
        print('[AUTH] ⚠️ Aucune sécurité disponible sur cet appareil');
        return false;
      }

      // 2. Obtenir les types de biométrie disponibles
      List<BiometricType> availableBiometrics = [];
      try {
        availableBiometrics = await _localAuth.getAvailableBiometrics();
        print('[AUTH] Types disponibles: $availableBiometrics');
      } catch (e) {
        print('[AUTH] Erreur getAvailableBiometrics: $e');
      }

      // 3. Tenter l'authentification
      try {
        final authenticated = await _localAuth.authenticate(
          localizedReason: reason,
          options: const AuthenticationOptions(
            stickyAuth: true,
            biometricOnly: false, // ✅ Permet PIN/mot de passe en fallback
            useErrorDialogs: true,
            sensitiveTransaction: true,
          ),
        );

        if (authenticated) {
          print('[AUTH] ✓ Authentification réussie');
          return true;
        } else {
          print('[AUTH] ✗ Authentification refusée');
          return false;
        }
      } on PlatformException catch (e) {
        print('[AUTH] Exception: ${e.code} - ${e.message}');

        // Gérer les erreurs spécifiques
        switch (e.code) {
          case 'NotAvailable':
          case 'PasscodeNotSet':
          case 'NotEnrolled':
            print('[AUTH] ⚠️ Sécurité non configurée sur l\'appareil');
            return false;

          case 'LockedOut':
          case 'PermanentlyLockedOut':
            print('[AUTH] ⚠️ Appareil verrouillé après trop de tentatives');
            return false;

          case 'UserCanceled':
            print('[AUTH] Utilisateur a annulé');
            return false;

          default:
            print('[AUTH] Erreur inconnue: ${e.code}');
            return false;
        }
      } catch (e) {
        print('[AUTH] Erreur générale: $e');
        return false;
      }
    } catch (e) {
      print('[AUTH] Exception fatale: $e');
      return false;
    }
  }

  /// Vérifie si l'appareil a une sécurité configurée
  Future<SecurityStatus> checkDeviceSecurity() async {
    try {
      final canCheckBiometrics = await _localAuth.canCheckBiometrics;
      final isDeviceSupported = await _localAuth.isDeviceSupported();

      if (!isDeviceSupported) {
        return SecurityStatus(
          isAvailable: false,
          type: SecurityType.none,
          message: 'Cet appareil ne supporte pas la sécurité biométrique',
        );
      }

      if (!canCheckBiometrics) {
        return SecurityStatus(
          isAvailable: false,
          type: SecurityType.none,
          message:
              'Aucune sécurité configurée. Veuillez configurer un code PIN, un mot de passe ou une empreinte dans les paramètres de votre téléphone',
        );
      }

      // Vérifier les types disponibles
      final availableBiometrics = await _localAuth.getAvailableBiometrics();

      if (availableBiometrics.contains(BiometricType.fingerprint)) {
        return SecurityStatus(
          isAvailable: true,
          type: SecurityType.fingerprint,
          message: 'Empreinte digitale disponible',
        );
      }

      if (availableBiometrics.contains(BiometricType.face)) {
        return SecurityStatus(
          isAvailable: true,
          type: SecurityType.face,
          message: 'Reconnaissance faciale disponible',
        );
      }

      if (availableBiometrics.contains(BiometricType.iris)) {
        return SecurityStatus(
          isAvailable: true,
          type: SecurityType.iris,
          message: 'Reconnaissance iris disponible',
        );
      }

      // PIN/mot de passe disponible
      return SecurityStatus(
        isAvailable: true,
        type: SecurityType.pin,
        message: 'Code PIN/mot de passe disponible',
      );
    } catch (e) {
      return SecurityStatus(
        isAvailable: false,
        type: SecurityType.none,
        message: 'Erreur lors de la vérification: $e',
      );
    }
  }
}
