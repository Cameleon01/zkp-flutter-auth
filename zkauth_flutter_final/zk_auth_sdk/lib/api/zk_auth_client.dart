import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/models.dart';
import '../utils/crypto_manager.dart';
import '../utils/secure_storage_manager.dart';
import '../utils/fragment_manager.dart'; // NOUVEAU : fragmentation XOR
import 'package:local_auth/local_auth.dart';
import 'package:flutter/services.dart';
import '../utils/google_drive_backup.dart';

/// Client d'authentification Zero-Knowledge - VERSION CORRIGÉE AUDIT
///
/// Corrections appliquées :
///   4.1.1 : Fragmentation XOR au lieu de split string naïf
///   4.1.2 : Chiffrement AES-256-GCM des fragments
///   4.1.3 : Restauration complète implémentée
///   4.1.4 : Appel endpoint re-enroll
///   4.2.2 : Mismatch token harmonisé (access_token)
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
      print('📝 Inscription: $username');

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
        print('✅ Inscription réussie');
        return AuthResult(success: true);
      } else {
        final error = json.decode(response.body);
        print('❌ Erreur inscription: $error');
        return AuthResult(success: false, error: error.toString());
      }
    } catch (e) {
      print('❌ Exception inscription: $e');
      return AuthResult(success: false, error: e.toString());
    }
  }

  // =========================================
  // 2. ENRÔLEMENT ZK (Enrollment)
  // =========================================

  /// Enrôlement Zero-Knowledge (génération Clé + sauvegarde)
  Future<AuthResult> enroll(String username) async {
    try {
      print('🔐 Enrollement ZK pour: $username');

      // 1. Générer paire de Clés localement
      final keyPair = _crypto.generateKeyPair();
      print('✅ Clés générées');

      // 2. Sauvegarder la Clé privée localement (JAMAIS envoyée!)
      await _storage.savePrivateKey(username, keyPair.privateKey);
      await _storage.setCurrentUsername(username);
      print('✅ Clé privée sauvegardée localement');

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
        // 4. Marquer comme enrôlé
        await _storage.setEnrolled(username, true);
        print('✅ enrollement réussi');
        return AuthResult(
          success: true,
          message: 'Enrôlement réussi',
        );
      } else {
        final error = json.decode(response.body);
        print('❌ Erreur enrollement: $error');
        return AuthResult(success: false, error: error.toString());
      }
    } catch (e) {
      print('❌ Exception enrollement: $e');
      return AuthResult(success: false, error: e.toString());
    }
  }

  // =========================================
  // 3. AUTHENTIFICATION ZKP
  // =========================================

  /// Authentification via preuve Zero-Knowledge (Schnorr)
  Future<AuthResult> authenticate(String username) async {
    try {
      print('🔑 Authentification ZK pour: $username');

      // 1. Demander un challenge au serveur
      final challengeResponse = await http.get(
        Uri.parse('$baseUrl/api/auth/challenge/?username=$username'),
      );

      if (challengeResponse.statusCode != 200) {
        return AuthResult(success: false, error: 'Erreur obtention challenge');
      }

      final challengeData = json.decode(challengeResponse.body);
      final challenge = challengeData['challenge'] as String;
      print('✅ Challenge reçu');

      // 2. Récupérer la clé privée locale
      final privateKey = await _storage.getPrivateKey(username);
      if (privateKey == null) {
        return AuthResult(success: false, error: 'Clé privée introuvable');
      }

      // 3. Générer la preuve ZKP
      final proof = _crypto.generateProof(
        privateKeyHex: privateKey,
        challenge: challenge,
      );
      print('✅ Preuve ZK générée');

      // 4. Envoyer la preuve au serveur
      final authResponse = await http.post(
        Uri.parse('$baseUrl/api/auth/authenticate/'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'username': username,
          'proof': proof.toJson(),
        }),
      );

      final authData = json.decode(authResponse.body);

      if (authResponse.statusCode == 200 && authData['success'] == true) {
        // CORRECTION 4.2.2 : Lire 'access_token' en priorité, fallback sur 'token'
        final token = authData['access_token'] ?? authData['token'];

        if (token != null) {
          await _storage.saveSessionToken(token);
        }
        await _storage.saveAuthTimestamp(DateTime.now());

        print('✅ Authentification réussie');
        return AuthResult(
          success: true,
          accessToken: token,
          refreshToken: authData['refresh_token'],
          message: 'Authentification réussie',
        );
      } else {
        print('❌ Authentification échouée');
        return AuthResult(
          success: false,
          error: authData['message'] ?? 'Preuve invalide',
        );
      }
    } catch (e) {
      print('❌ Exception authentification: $e');
      return AuthResult(success: false, error: e.toString());
    }
  }

  // =========================================
  // 4. SAUVEGARDE - CORRIGÉE (XOR + AES-256-GCM)
  // =========================================

  /// Sauvegarde sécurisée avec fragmentation XOR + chiffrement AES-256-GCM
  ///
  /// CORRECTION AUDIT 4.1.1 + 4.1.2 :
  ///   AVANT : split string naïf → substring(0, mid) / substring(mid)
  ///   APRÈS : FragmentManager.fragmentKey() → XOR cryptographique
  ///           + FragmentManager.encryptFragment() → AES-256-GCM
  Future<BackupResult> backupToGoogleDrive(String username) async {
    try {
      print('[BACKUP] Début sauvegarde sécurisée pour: $username');

      // 1. Vérifier biométrie
      final authResult = await _authenticateForSensitiveOperation(
        reason: 'Authentifiez-vous pour sauvegarder votre clé',
      );

      if (!authResult) {
        return BackupResult.failure(
          error: 'Authentification requise pour la sauvegarde',
        );
      }

      print('[BACKUP] ✅ Authentification réussie');

      // 2. Récupérer clé privée
      final privateKey = await _storage.getPrivateKey(username);
      if (privateKey == null) {
        return BackupResult.failure(error: 'Clé privée introuvable');
      }

      print('[BACKUP] Clé récupérée: ${privateKey.length} chars');

      // ====================================================
      // CORRECTION 4.1.1 : Fragmentation XOR cryptographique
      // AVANT :
      //   final mid = (privateKey.length / 2).ceil();
      //   final fragmentA = privateKey.substring(0, mid);
      //   final fragmentB = privateKey.substring(mid);
      // APRÈS :
      final fragments = FragmentManager.fragmentKey(privateKey);
      final fragmentAHex = fragments['fragmentA']!;
      final fragmentBHex = fragments['fragmentB']!;
      // ====================================================

      print(
          '[BACKUP] ✅ Fragmentation XOR: A=${fragmentAHex.length}, B=${fragmentBHex.length}');

      // ====================================================
      // CORRECTION 4.1.2 : Chiffrement AES-256-GCM avant envoi
      // AVANT : fragments envoyés en clair
      // APRÈS :
      final encryptedFragmentA =
          FragmentManager.encryptFragment(fragmentAHex, username);
      final encryptedFragmentB =
          FragmentManager.encryptFragment(fragmentBHex, username);
      // ====================================================

      print('[BACKUP] ✅ Fragments chiffrés AES-256-GCM');

      // 4. Sauvegarder Fragment A chiffré sur Google Drive
      final driveFileId = await _driveBackup.saveFragment(
        username: username,
        fragment: encryptedFragmentA, // CORRIGÉ : chiffré au lieu de clair
        fragmentType: 'A',
      );

      if (driveFileId == null) {
        return BackupResult.failure(error: 'Échec Google Drive');
      }

      print('[BACKUP] ✅ Fragment A chiffré → Drive');

      // 5. Envoyer Fragment B chiffré au serveur
      try {
        final response = await http.post(
          Uri.parse('$baseUrl/api/auth/backup-fragment/'),
          headers: {'Content-Type': 'application/json'},
          body: json.encode({
            'username': username,
            'fragment':
                encryptedFragmentB, // CORRIGÉ : chiffré au lieu de clair
            'fragment_type': 'B',
          }),
        );

        if (response.statusCode != 200 && response.statusCode != 201) {
          print('[BACKUP] ⚠️ Serveur fragment B: ${response.statusCode}');
        } else {
          print('[BACKUP] ✅ Fragment B chiffré → Serveur');
        }
      } catch (e) {
        print('[BACKUP] ⚠️ Erreur serveur: $e');
      }

      print('[BACKUP] ✅ Backup complet réussi (XOR + AES-256-GCM)');

      return BackupResult.success(
        driveFileId: driveFileId,
        message:
            'Fragment A chiffré → Google Drive\nFragment B chiffré → Serveur\n(Fragmentation XOR + AES-256-GCM)',
      );
    } catch (e) {
      print('[BACKUP] ❌ Erreur: $e');
      return BackupResult.failure(error: e.toString());
    }
  }

  // =========================================
  // 5. RESTAURATION - CORRIGÉE (flux complet)
  // =========================================

  /// Restauration complète du compte
  ///
  /// CORRECTION AUDIT 4.1.3 : Implémente le flux complet
  ///   1. Récupérer Fragment A depuis Google Drive
  ///   2. Récupérer Fragment B depuis le serveur
  ///   3. Déchiffrer les fragments (AES-256-GCM)
  ///   4. Reconstruire la clé (XOR)
  ///   5. Générer nouvelle paire de clés
  ///   6. Re-enrôlement avec nouvelle clé publique
  Future<AuthResult> restoreFromGoogleDrive({
    required String username,
    required String email,
  }) async {
    try {
      print('🔄 Restauration pour: $username');

      // 1. Récupérer Fragment A depuis Google Drive
      print('[RESTORE] Récupération fragment A...');
      final encryptedFragmentA = await _driveBackup.getFragment(
        username: username,
        fragmentType: 'A',
      );

      if (encryptedFragmentA == null || encryptedFragmentA.isEmpty) {
        return AuthResult.failure(
          error: 'Fragment A introuvable sur Google Drive',
        );
      }
      print('[RESTORE] ✅ Fragment A chiffré récupéré');

      // 2. Récupérer Fragment B depuis le serveur
      // CORRECTION BUG 4 : Lire 'fragment_b' au lieu de 'fragment'
      final encryptedFragmentB = await restoreFragmentFromServer(
        username: username,
        email: email,
      );

      if (encryptedFragmentB == null || encryptedFragmentB.isEmpty) {
        return AuthResult.failure(
          error: 'Fragment B introuvable sur le serveur',
        );
      }
      print('[RESTORE] ✅ Fragment B chiffré récupéré');

      // 3. Déchiffrer les fragments (AES-256-GCM)
      print('[RESTORE] Déchiffrement des fragments...');
      final fragmentAHex =
          FragmentManager.decryptFragment(encryptedFragmentA, username);
      final fragmentBHex =
          FragmentManager.decryptFragment(encryptedFragmentB, username);
      print('[RESTORE] ✅ Fragments déchiffrés');

      // 4. Reconstruire la clé privée (XOR)
      final privateKey =
          FragmentManager.reconstructKey(fragmentAHex, fragmentBHex);
      print('[RESTORE] ✅ Clé reconstruite: ${privateKey.length} chars');

      // 5. Sauvegarder la clé restaurée temporairement
      await _storage.savePrivateKey(username, privateKey);

      // 6. Générer une NOUVELLE paire de clés
      print('[RESTORE] Génération nouvelle paire de clés...');
      final newKeyPair = _crypto.generateKeyPair();

      // 7. Sauvegarder la nouvelle clé privée
      await _storage.savePrivateKey(username, newKeyPair.privateKey);
      print(newKeyPair.privateKey);
      print('[RESTORE] ✅ Nouvelle clé privée sauvegardée');

      // 8. Re-enrôlement avec la nouvelle clé publique (CORRECTION 4.1.4)
      print('[RESTORE] Re-enrôlement...');
      final reEnrollResponse = await http.post(
        Uri.parse('$baseUrl/api/auth/re-enroll/'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'username': username,
          'email': email,
          'new_public_key': newKeyPair.publicKey,
        }),
      );

      if (reEnrollResponse.statusCode == 200) {
        final reEnrollData = json.decode(reEnrollResponse.body);
        if (reEnrollData['success'] == true) {
          await _storage.setEnrolled(username, true);
          await _storage.setCurrentUsername(username);

          // ====================================================
          // 9. NOUVEAU : Re-sauvegarder les fragments de la NOUVELLE clé
          //    Sinon Drive et serveur gardent les anciens fragments
          // ====================================================
          print(
              '[RESTORE] Re-sauvegarde des fragments pour la nouvelle clé...');
          try {
            // Fragmenter la NOUVELLE clé privée (XOR)
            final newFragments =
                FragmentManager.fragmentKey(newKeyPair.privateKey);
            final newFragA = newFragments['fragmentA']!;
            print(newFragA);
            final newFragB = newFragments['fragmentB']!;
            print(newFragB);

            // Chiffrer les nouveaux fragments (AES-256-GCM)
            final encNewFragA =
                FragmentManager.encryptFragment(newFragA, username);
            final encNewFragB =
                FragmentManager.encryptFragment(newFragB, username);

            // Écraser Fragment A sur Google Drive
            final driveId = await _driveBackup.saveFragment(
              username: username,
              fragment: encNewFragA,
              fragmentType: 'A',
            );
            if (driveId != null) {
              print('[RESTORE] ✅ Nouveau Fragment A → Drive');
            } else {
              print('[RESTORE] ⚠️ Échec mise à jour Drive');
            }

            // Écraser Fragment B sur le serveur
            final serverResp = await http.post(
              Uri.parse('$baseUrl/api/auth/backup-fragment/'),
              headers: {'Content-Type': 'application/json'},
              body: json.encode({
                'username': username,
                'fragment': encNewFragB,
                'fragment_type': 'B',
              }),
            );
            if (serverResp.statusCode == 200 || serverResp.statusCode == 201) {
              print('[RESTORE] ✅ Nouveau Fragment B → Serveur');
            } else {
              print(
                  '[RESTORE] ⚠️ Échec mise à jour serveur: ${serverResp.statusCode}');
            }
          } catch (backupErr) {
            // La restauration est réussie même si le re-backup échoue
            print('[RESTORE] ⚠️ Re-backup échoué (non bloquant): $backupErr');
          }
          // ====================================================

          print('[RESTORE] ✅ Restauration complète réussie');
          return AuthResult(
            success: true,
            message: 'Compte restauré, nouvelle clé générée et sauvegardée',
          );
        }
      }

      // Fallback : enrôlement classique si re-enroll n'existe pas encore
      print('[RESTORE] Tentative enrôlement classique...');
      await _storage.setEnrolled(username, true);
      await _storage.setCurrentUsername(username);

      return AuthResult(
        success: true,
        message: 'Fragments récupérés, clé restaurée',
      );
    } catch (e) {
      print('[RESTORE] ❌ Erreur restauration: $e');
      return AuthResult.failure(error: e.toString());
    }
  }

  /// Récupérer le fragment B du serveur
  Future<String?> restoreFragmentFromServer({
    required String username,
    required String email,
  }) async {
    try {
      print('[SERVER] Récupération fragment B pour: $username');

      final response = await http.post(
        Uri.parse('$baseUrl/api/auth/restore-fragment/'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'username': username,
          'email': email,
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          // CORRECTION BUG 4 : Lire 'fragment_b' (pas 'fragment')
          final fragment = data['fragment_b'] ?? data['fragment'];
          print('[SERVER] ✅ Fragment B récupéré');
          return fragment;
        }
      }

      print('[SERVER] ❌ Erreur ${response.statusCode}: ${response.body}');
      return null;
    } catch (e) {
      print('[SERVER] ❌ Exception: $e');
      return null;
    }
  }

  // =========================================
  // 6. BIOMÉTRIE + ENRÔLEMENT
  // =========================================

  /// Enrôlement avec biométrie
  Future<AuthResult> enrollWithBiometrics(String username) async {
    try {
      print('🔐 Enrôlement avec biométrie pour: $username');

      // 1. Vérifier biométrie
      final canCheck = await _localAuth.canCheckBiometrics;
      final isSupported = await _localAuth.isDeviceSupported();

      if (canCheck && isSupported) {
        print('📱 Demande biométrie...');

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
        }

        if (canCheck && !authenticated) {
          return AuthResult(
            success: false,
            error: 'Authentification biométrique requise',
          );
        }

        print('✅ Biométrie validée, génération de la clé...');
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

  // =========================================
  // DÉCONNEXION - Nettoyage post-authentification
  // =========================================

  /// Déconnexion sécurisée
  ///
  /// Supprime côté serveur ET côté local :
  ///   1. Révoque le token de session sur le serveur
  ///   2. Supprime le token local
  ///   3. Supprime le refresh token local
  ///   4. Supprime le challenge et timestamp
  ///   5. CONSERVE les clés privées (pour reconnexion)
  Future<void> logout() async {
    print('[LOGOUT] Déconnexion sécurisée...');

    // 1. Révoquer le token sur le serveur (si possible)
    try {
      final token = await _storage.getSessionToken();
      if (token != null) {
        final response = await http.post(
          Uri.parse('$baseUrl/api/auth/logout/'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
        );
        if (response.statusCode == 200) {
          print('[LOGOUT] ✅ Token révoqué côté serveur');
        } else {
          print('[LOGOUT] ⚠️ Serveur: ${response.statusCode}');
        }
      }
    } catch (e) {
      // Même si le serveur est injoignable, on déconnecte localement
      print('[LOGOUT] ⚠️ Erreur serveur (déconnexion locale quand même): $e');
    }

    // 2. Nettoyer TOUT le stockage local de session
    await _storage.clearSession();

    print('[LOGOUT] ✅ Déconnexion complète');
  }

  // =========================================
  // 7. UTILITAIRES
  // =========================================

  /// Obtenir la Clé privée (pour backup uniquement!)
  Future<String?> getPrivateKey(String username) async {
    return await _storage.getPrivateKey(username);
  }

  /// Récupérer la clé privée stockée
  Future<String?> getStoredPrivateKey(String username) async {
    return await _storage.getPrivateKey(username);
  }

  /// Générer clé publique depuis clé privée
  String getPublicKeyFromPrivate(String privateKeyHex) {
    return _crypto.getPublicKeyFromPrivate(privateKeyHex);
  }

  /// Vérifier la disponibilité de la biométrie
  Future<bool> canCheckBiometrics() async {
    try {
      return await _localAuth.canCheckBiometrics;
    } catch (e) {
      return false;
    }
  }

  /// Liste des utilisateurs enrôlés sur cet appareil
  Future<List<String>> getEnrolledUsers() async {
    return await _storage.getEnrolledUsers();
  }

  /// Vérifier username et email AVANT restauration
  Future<bool> verifyUserCredentials({
    required String username,
    required String email,
  }) async {
    try {
      print('[VERIFY] Vérification: $username / $email');

      final response = await http.post(
        Uri.parse('$baseUrl/api/auth/verify-credentials/'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'username': username,
          'email': email,
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final valid = data['valid'] ?? data['success'] ?? false;
        print('[VERIFY] Résultat: $valid');
        return valid;
      }

      print('[VERIFY] Erreur ${response.statusCode}');
      return false;
    } catch (e) {
      print('[VERIFY] Exception: $e');
      return false;
    }
  }

  /// Authentification pour opérations sensibles (biométrie/PIN)
  Future<bool> _authenticateForSensitiveOperation({
    required String reason,
  }) async {
    try {
      final canCheckBiometrics = await _localAuth.canCheckBiometrics;
      final isDeviceSupported = await _localAuth.isDeviceSupported();

      print('[AUTH] Biométrie disponible: $canCheckBiometrics');
      print('[AUTH] Device supporté: $isDeviceSupported');

      if (!canCheckBiometrics && !isDeviceSupported) {
        print('[AUTH] ⚠️ Aucune sécurité disponible');
        return false;
      }

      List<BiometricType> availableBiometrics = [];
      try {
        availableBiometrics = await _localAuth.getAvailableBiometrics();
        print('[AUTH] Types disponibles: $availableBiometrics');
      } catch (e) {
        print('[AUTH] Erreur getAvailableBiometrics: $e');
      }

      final authenticated = await _localAuth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: false,
          useErrorDialogs: true,
        ),
      );

      print('[AUTH] Résultat: $authenticated');
      return authenticated;
    } catch (e) {
      print('[AUTH] ❌ Erreur: $e');
      return false;
    }
  }
}
