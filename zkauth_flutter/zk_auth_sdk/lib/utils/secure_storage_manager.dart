import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Gestionnaire de stockage sécurisé pour les Clés privées et sessions
/// Support multi-utilisateurs avec gestion de session
class SecureStorageManager {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
    ),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  // =========================================
  // CLES PRIVEES (Permanent - Survit logout)
  // =========================================

  /// Sauvegarder la Clé privée pour un username
  Future<void> savePrivateKey(String username, String privateKey) async {
    try {
      print('ðŸ’¾ [SecureStorage] Sauvegarde Clé pour: $username');
      await _storage.write(key: 'zk_private_key_$username', value: privateKey);
      print(' [SecureStorage] Clé sauvegardée');
    } catch (e) {
      print('Vérifier[SecureStorage] Erreur sauvegarde: $e');
      rethrow;
    }
  }

  /// Récupérer la Clé privée d'un username
  Future<String?> getPrivateKey(String username) async {
    try {
      final privateKey = await _storage.read(key: 'zk_private_key_$username');
      if (privateKey != null) {
        print(' [SecureStorage] Clé trouvée pour: $username');
      } else {
        print('âš ï¸  [SecureStorage] Pas de Clé pour: $username');
      }
      return privateKey;
    } catch (e) {
      print('Vérifier[SecureStorage] Erreur lecture: $e');
      return null;
    }
  }

  // =========================================
  // STATUT ENROLEMENT (Permanent)
  // =========================================

  /// Marquer comme enrÃ´lé
  Future<void> setEnrolled(String username, bool enrolled) async {
    try {
      await _storage.write(
        key: 'zk_enrolled_$username',
        value: enrolled.toString(),
      );
      print(' [SecureStorage] $username enrÃ´lé: $enrolled');
    } catch (e) {
      print('Vérifier[SecureStorage] Erreur statut: $e');
    }
  }

  /// Vérifier si enrÃ´lé
  Future<bool> isEnrolled(String username) async {
    try {
      final value = await _storage.read(key: 'zk_enrolled_$username');
      return value == 'true';
    } catch (e) {
      print('Vérifier[SecureStorage] Erreur vérification: $e');
      return false;
    }
  }

  // =========================================
  // SESSION (Temporaire - Supprimé au logout)
  // =========================================

  /// Sauvegarder le username actuel
  Future<void> setCurrentUsername(String username) async {
    try {
      await _storage.write(key: 'zk_current_username', value: username);
      print(' [SecureStorage] Username actuel: $username');
    } catch (e) {
      print('Vérifier[SecureStorage] Erreur username: $e');
    }
  }

  /// Récupérer le username actuel
  Future<String?> getCurrentUsername() async {
    try {
      return await _storage.read(key: 'zk_current_username');
    } catch (e) {
      return null;
    }
  }

  /// Sauvegarder le token de session JWT
  Future<void> saveSessionToken(String token) async {
    try {
      await _storage.write(key: 'zk_session_token', value: token);
      print(' [SecureStorage] Token session sauvegardé');
    } catch (e) {
      print('Vérifier[SecureStorage] Erreur token: $e');
    }
  }

  /// Récupérer le token de session
  Future<String?> getSessionToken() async {
    try {
      return await _storage.read(key: 'zk_session_token');
    } catch (e) {
      return null;
    }
  }

  /// Sauvegarder le challenge temporaire
  Future<void> saveChallenge(String challenge) async {
    try {
      await _storage.write(key: 'zk_last_challenge', value: challenge);
      print(' [SecureStorage] Challenge sauvegardé');
    } catch (e) {
      print('Vérifier[SecureStorage] Erreur challenge: $e');
    }
  }

  /// Récupérer le dernier challenge
  Future<String?> getChallenge() async {
    try {
      return await _storage.read(key: 'zk_last_challenge');
    } catch (e) {
      return null;
    }
  }

  /// Sauvegarder le timestamp d'authentification
  Future<void> saveAuthTimestamp(DateTime timestamp) async {
    try {
      await _storage.write(
        key: 'zk_last_auth_timestamp',
        value: timestamp.toIso8601String(),
      );
      print(' [SecureStorage] Timestamp auth sauvegardé');
    } catch (e) {
      print('Vérifier[SecureStorage] Erreur timestamp: $e');
    }
  }

  /// Récupérer le timestamp d'authentification
  Future<DateTime?> getAuthTimestamp() async {
    try {
      final value = await _storage.read(key: 'zk_last_auth_timestamp');
      if (value == null) return null;
      return DateTime.parse(value);
    } catch (e) {
      return null;
    }
  }

  // =========================================
  // DECONNEXION
  // =========================================

  /// Déconnexion complÃ¨te (supprime session + tokens)
  /// âš ï¸ CONSERVE les Clés privées pour reconnexion
  Future<void> clearSession() async {
    try {
      print('ðŸ—‘ï¸  [SecureStorage] Déconnexion...');

      // 1. Supprimer le username actuel
      await _storage.delete(key: 'zk_current_username');

      // 2. Supprimer les tokens de session
      await _storage.delete(key: 'zk_session_token');
      await _storage.delete(key: 'zk_refresh_token');

      // 3. Supprimer les données temporaires
      await _storage.delete(key: 'zk_last_challenge');
      await _storage.delete(key: 'zk_last_auth_timestamp');

      // 4. Supprimer le cache utilisateur
      await _storage.delete(key: 'zk_user_cache');

      //  Les Clés privées (zk_private_key_*) restent
      //  Le statut enrolled (zk_enrolled_*) reste

      print(
          ' [SecureStorage] Session fermée (Clés cryptographiques conservées)');
    } catch (e) {
      print('Vérifier[SecureStorage] Erreur déconnexion: $e');
    }
  }

  // =========================================
  // SUPPRESSION COMPLÃˆTE
  // =========================================

  /// Supprimer TOUT (reset complet de l'application)
  Future<void> deleteAll() async {
    try {
      print('ðŸ—‘ï¸  [SecureStorage] Suppression complÃ¨te...');
      await _storage.deleteAll();
      print(' [SecureStorage] Toutes données supprimées');
    } catch (e) {
      print('Vérifier[SecureStorage] Erreur suppression: $e');
    }
  }

  /// Supprimer un utilisateur spécifique (révocation)
  Future<void> deleteUser(String username) async {
    try {
      print('ðŸ—‘ï¸  [SecureStorage] Suppression user: $username');

      // Supprimer Clé privée
      await _storage.delete(key: 'zk_private_key_$username');

      // Supprimer statut enrolled
      await _storage.delete(key: 'zk_enrolled_$username');

      // Si c'est l'utilisateur actuel, supprimer la session
      final currentUser = await getCurrentUsername();
      if (currentUser == username) {
        await clearSession();
      }

      print(' [SecureStorage] User supprimé');
    } catch (e) {
      print('Vérifier[SecureStorage] Erreur suppression user: $e');
    }
  }

  // =========================================
  // UTILITAIRES
  // =========================================

  /// Lister tous les utilisateurs enrÃ´lés sur cet appareil
  Future<List<String>> getEnrolledUsers() async {
    try {
      final allKeys = await _storage.readAll();
      final users = <String>[];

      for (var key in allKeys.keys) {
        if (key.startsWith('zk_private_key_')) {
          final username = key.replaceFirst('zk_private_key_', '');
          users.add(username);
        }
      }

      print('ðŸ“‹ [SecureStorage] Users enrÃ´lés: ${users.length}');
      return users;
    } catch (e) {
      print('Vérifier[SecureStorage] Erreur liste users: $e');
      return [];
    }
  }

  /// Vérifier si un utilisateur a une Clé privée
  Future<bool> hasPrivateKey(String username) async {
    final key = await getPrivateKey(username);
    return key != null;
  }

  /// Debug: Afficher toutes les Clés stockées (dev only)
  Future<void> debugPrintAllKeys() async {
    try {
      final allKeys = await _storage.readAll();
      print('ðŸ” [SecureStorage Debug] Clés stockées:');
      for (var key in allKeys.keys) {
        print('   - $key');
      }
    } catch (e) {
      print('Vérifier[SecureStorage] Erreur debug: $e');
    }
  }
}
