/// ZK-AUTH Client - VERSION CORRIGEE AUDIT
/// Corrections :
///   4.2.2 : Mismatch token harmonise (access_token)
///   4.3(f) : baseUrl configurable via ZKAuthConfig
///   4.1.1 : Fragmentation XOR via FragmentManager
///   4.1.2 : Chiffrement AES-256-GCM des fragments
///   4.3(e) : Suppression des print() de debug
///
/// Emplacement : lib/services/zk_auth_client.dart
library;

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import '../config/zkauth_config.dart';
import 'fragment_manager.dart';

class ZKAuthClient {
  final String baseUrl;
  final CryptoManager _crypto;
  final SecureStorageManager _storage;
  String? _currentToken;
  String? _refreshToken;

  ZKAuthClient({String? baseUrl})
    : baseUrl = baseUrl ?? ZKAuthConfig.baseUrl,
      _crypto = CryptoManager(),
      _storage = SecureStorageManager();

  // ============================================================
  // INSCRIPTION
  // ============================================================

  Future<Map<String, dynamic>> register(
    String username,
    String email, {
    String? phone,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/auth/register/'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'username': username,
        'email': email,
        if (phone != null) 'phone': phone,
      }),
    );

    return jsonDecode(response.body);
  }

  // ============================================================
  // ENROLEMENT
  // ============================================================

  Future<Map<String, dynamic>> enroll(String username) async {
    // Generer paire de cles secp256k1
    final keyPair = _crypto.generateKeyPair();
    final publicKeyHex = keyPair['publicKey']!;
    final privateKeyHex = keyPair['privateKey']!;

    // Stocker la cle privee localement (Secure Enclave / Keystore)
    await _storage.savePrivateKey(username, privateKeyHex);

    // Envoyer UNIQUEMENT la cle publique au serveur
    final response = await http.post(
      Uri.parse('$baseUrl/api/auth/enroll/'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'username': username, 'public_key': publicKeyHex}),
    );

    return jsonDecode(response.body);
  }

  // ============================================================
  // AUTHENTIFICATION ZKP
  // ============================================================

  Future<Map<String, dynamic>> authenticate(String username) async {
    // 1. Obtenir un challenge du serveur
    final challengeResponse = await http.get(
      Uri.parse('$baseUrl/api/auth/challenge/?username=$username'),
    );
    final challengeData = jsonDecode(challengeResponse.body);

    if (challengeData['success'] != true) {
      return challengeData;
    }

    final challenge = challengeData['challenge'] as String;

    // 2. Recuperer la cle privee locale
    final privateKeyHex = await _storage.getPrivateKey(username);
    if (privateKeyHex == null) {
      return {'success': false, 'message': 'Cle privee non trouvee'};
    }

    // 3. Generer la preuve ZKP (Schnorr)
    final proof = _crypto.generateSchnorrProof(privateKeyHex, challenge);

    // 4. Envoyer la preuve au serveur
    final authResponse = await http.post(
      Uri.parse('$baseUrl/api/auth/authenticate/'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'username': username,
        'proof': {'r': proof['r'], 's': proof['s'], 'challenge': challenge},
      }),
    );

    final authData = jsonDecode(authResponse.body);

    // CORRECTION 4.2.2 : Lire 'access_token' (harmonise avec le serveur)
    // Le serveur retourne maintenant les deux cles pour retrocompatibilite
    if (authData['success'] == true) {
      _currentToken = authData['access_token'] ?? authData['token'];
      _refreshToken = authData['refresh_token'];

      // Sauvegarder le token
      await _storage.saveToken(username, _currentToken!);
      if (_refreshToken != null) {
        await _storage.saveRefreshToken(username, _refreshToken!);
      }
    }

    return authData;
  }

  // ============================================================
  // BACKUP - CORRECTION 4.1.1 + 4.1.2
  // ============================================================

  /// Sauvegarder la cle privee de maniere fragmentee
  ///
  /// AVANT : split string naif (VULNERABLE)
  /// APRES : fragmentation XOR + chiffrement AES-256-GCM
  Future<Map<String, dynamic>> backup(String username) async {
    // Recuperer la cle privee
    final privateKeyHex = await _storage.getPrivateKey(username);
    if (privateKeyHex == null) {
      return {'success': false, 'message': 'Cle privee non trouvee'};
    }

    // CORRECTION 4.1.1 : Fragmentation XOR cryptographique
    final fragments = FragmentManager.fragmentKey(privateKeyHex);

    // CORRECTION 4.1.2 : Chiffrement AES-256-GCM avant transmission
    final encryptedFragmentA = FragmentManager.encryptFragment(
      fragments['fragmentA']!,
      username,
    );
    final encryptedFragmentB = FragmentManager.encryptFragment(
      fragments['fragmentB']!,
      username,
    );

    // Fragment A -> Google Drive (via l'API Google Drive)
    // TODO: Implementer l'envoi reel via Google Drive API
    // Pour l'instant, sauvegarder localement en attendant
    await _storage.saveFragmentA(username, encryptedFragmentA);

    // Fragment B -> Serveur ZK-AUTH (chiffre)
    final response = await http.post(
      Uri.parse('$baseUrl/api/auth/backup-fragment/'),
      headers: {
        'Content-Type': 'application/json',
        if (_currentToken != null) 'Authorization': 'Bearer $_currentToken',
      },
      body: jsonEncode({
        'username': username,
        'fragment': encryptedFragmentB,
        'fragment_type': 'B',
      }),
    );

    return jsonDecode(response.body);
  }

  // ============================================================
  // RESTAURATION - CORRECTION 4.1.3 (flux complet)
  // ============================================================

  /// Restauration complete du compte
  ///
  /// Flux :
  ///   1. Verifier identifiants (username + email)
  ///   2. Recuperer Fragment A depuis Google Drive
  ///   3. Recuperer Fragment B depuis le serveur
  ///   4. Dechiffrer et reconstruire la cle
  ///   5. Generer une nouvelle paire de cles
  ///   6. Re-enrolement avec la nouvelle cle publique
  Future<Map<String, dynamic>> restore(String username, String email) async {
    // Etape 1 : Verifier les identifiants
    final verifyResponse = await http.post(
      Uri.parse('$baseUrl/api/auth/verify-credentials/'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'username': username, 'email': email}),
    );
    final verifyData = jsonDecode(verifyResponse.body);

    if (verifyData['success'] != true) {
      return {'success': false, 'message': 'Identifiants invalides'};
    }

    // Etape 2 : Recuperer Fragment A (Google Drive ou stockage local)
    final encryptedFragmentA = await _storage.getFragmentA(username);
    if (encryptedFragmentA == null) {
      return {
        'success': false,
        'message': 'Fragment A non trouve (verifier Google Drive)',
      };
    }

    // Etape 3 : Recuperer Fragment B depuis le serveur
    final restoreResponse = await http.post(
      Uri.parse('$baseUrl/api/auth/restore-fragment/'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'username': username, 'email': email}),
    );
    final restoreData = jsonDecode(restoreResponse.body);

    if (restoreData['success'] != true) {
      return {
        'success': false,
        // CORRECTION bug 4 : Lire 'fragment_b' (pas 'fragment')
        'message': restoreData['message'] ?? 'Fragment B non trouve',
      };
    }

    // CORRECTION bug 4 : Lire 'fragment_b' au lieu de 'fragment'
    final encryptedFragmentB = restoreData['fragment_b'] as String;

    // Etape 4 : Dechiffrer les fragments
    final fragmentAHex = FragmentManager.decryptFragment(
      encryptedFragmentA,
      username,
    );
    final fragmentBHex = FragmentManager.decryptFragment(
      encryptedFragmentB,
      username,
    );

    // Etape 4b : Reconstruire la cle privee
    final restoredPrivateKeyHex = FragmentManager.reconstructKey(
      fragmentAHex,
      fragmentBHex,
    );

    // Etape 5 : Generer une NOUVELLE paire de cles
    final newKeyPair = _crypto.generateKeyPair();
    final newPublicKeyHex = newKeyPair['publicKey']!;
    final newPrivateKeyHex = newKeyPair['privateKey']!;

    // Sauvegarder la nouvelle cle privee
    await _storage.savePrivateKey(username, newPrivateKeyHex);

    // Etape 6 : Re-enrolement avec la nouvelle cle publique
    final reEnrollResponse = await http.post(
      Uri.parse('$baseUrl/api/auth/re-enroll/'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'username': username,
        'email': email,
        'new_public_key': newPublicKeyHex,
      }),
    );
    final reEnrollData = jsonDecode(reEnrollResponse.body);

    if (reEnrollData['success'] == true) {
      // Etape 7 : Detruire l'ancienne cle (securite)
      // L'ancienne cle est deja ecrasee par savePrivateKey ci-dessus

      return {
        'success': true,
        'message': 'Compte restaure et re-enrole avec succes',
      };
    }

    return reEnrollData;
  }

  // ============================================================
  // SESSION MANAGEMENT
  // ============================================================

  /// Verifier la validite du token actuel
  Future<bool> verifyToken() async {
    if (_currentToken == null) return false;

    final response = await http.post(
      Uri.parse('$baseUrl/api/auth/verify-token/'),
      headers: {'Authorization': 'Bearer $_currentToken'},
    );

    final data = jsonDecode(response.body);
    return data['valid'] == true;
  }

  /// Rafraichir le token
  Future<bool> refreshToken() async {
    if (_refreshToken == null) return false;

    final response = await http.post(
      Uri.parse('$baseUrl/api/auth/refresh-token/'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'refresh_token': _refreshToken}),
    );

    final data = jsonDecode(response.body);
    if (data['success'] == true) {
      _currentToken = data['access_token'] ?? data['token'];
      return true;
    }
    return false;
  }

  /// Deconnexion
  Future<void> logout() async {
    if (_currentToken != null) {
      await http.post(
        Uri.parse('$baseUrl/api/auth/logout/'),
        headers: {'Authorization': 'Bearer $_currentToken'},
      );
    }
    _currentToken = null;
    _refreshToken = null;
  }

  /// Token actuel
  String? get currentToken => _currentToken;
}

// ============================================================
// PLACEHOLDER CLASSES
// (Ces classes existent deja dans votre projet,
//  elles sont ici pour reference de l'interface attendue)
// ============================================================

/// Placeholder - Votre CryptoManager existant
class CryptoManager {
  Map<String, String> generateKeyPair() {
    // Votre implementation existante avec PointyCastle + secp256k1
    throw UnimplementedError('Use your existing CryptoManager');
  }

  Map<String, String> generateSchnorrProof(
    String privateKeyHex,
    String challenge,
  ) {
    // Votre implementation existante
    throw UnimplementedError('Use your existing CryptoManager');
  }
}

/// Placeholder - Votre SecureStorageManager existant
class SecureStorageManager {
  Future<void> savePrivateKey(String username, String key) async {
    throw UnimplementedError('Use your existing SecureStorageManager');
  }

  Future<String?> getPrivateKey(String username) async {
    throw UnimplementedError('Use your existing SecureStorageManager');
  }

  Future<void> saveToken(String username, String token) async {
    throw UnimplementedError('Use your existing SecureStorageManager');
  }

  Future<void> saveRefreshToken(String username, String token) async {
    throw UnimplementedError('Use your existing SecureStorageManager');
  }

  Future<void> saveFragmentA(String username, String fragment) async {
    throw UnimplementedError('Use your existing SecureStorageManager');
  }

  Future<String?> getFragmentA(String username) async {
    throw UnimplementedError('Use your existing SecureStorageManager');
  }
}
