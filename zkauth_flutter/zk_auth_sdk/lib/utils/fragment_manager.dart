import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:pointycastle/export.dart';

/// Gestionnaire de fragmentation cryptographique pour ZK-AUTH
///
/// CORRECTION AUDIT 4.1.1 + 4.1.2 :
///   AVANT : split string naïf → substring(0, mid) / substring(mid)
///           Chaque fragment exposait la moitié de la clé en clair
///   APRÈS : Fragmentation XOR + chiffrement AES-256-GCM
///           Aucun fragment ne révèle rien sans l'autre
///
/// Emplacement : zk_auth_sdk/lib/utils/fragment_manager.dart
class FragmentManager {
  /// Fragmentation cryptographique XOR
  ///
  /// Principe :
  ///   fragmentA = random bytes (même taille que la clé)
  ///   fragmentB = clé XOR fragmentA
  ///   Reconstruction : clé = fragmentA XOR fragmentB
  static Map<String, String> fragmentKey(String privateKeyHex) {
    final keyBytes = _hexToBytes(privateKeyHex);

    // Générer Fragment A : bytes aléatoires cryptographiquement sûrs
    final random = Random.secure();
    final fragmentA = Uint8List(keyBytes.length);
    for (int i = 0; i < fragmentA.length; i++) {
      fragmentA[i] = random.nextInt(256);
    }

    // Fragment B = clé XOR Fragment A
    final fragmentB = Uint8List(keyBytes.length);
    for (int i = 0; i < keyBytes.length; i++) {
      fragmentB[i] = keyBytes[i] ^ fragmentA[i];
    }

    print(
        '[FRAGMENT] Fragmentation XOR: A=${fragmentA.length} bytes, B=${fragmentB.length} bytes');

    return {
      'fragmentA': _bytesToHex(fragmentA),
      'fragmentB': _bytesToHex(fragmentB),
    };
  }

  /// Reconstruction de la clé depuis les deux fragments
  /// clé = fragmentA XOR fragmentB
  static String reconstructKey(String fragmentAHex, String fragmentBHex) {
    final fragmentA = _hexToBytes(fragmentAHex);
    final fragmentB = _hexToBytes(fragmentBHex);

    if (fragmentA.length != fragmentB.length) {
      throw ArgumentError(
          'Fragments de tailles différentes: A=${fragmentA.length}, B=${fragmentB.length}');
    }

    final keyBytes = Uint8List(fragmentA.length);
    for (int i = 0; i < fragmentA.length; i++) {
      keyBytes[i] = fragmentA[i] ^ fragmentB[i];
    }

    print('[FRAGMENT] Clé reconstruite: ${keyBytes.length} bytes');
    return _bytesToHex(keyBytes);
  }

  /// Chiffrement AES-256-GCM d'un fragment avant transmission
  ///
  /// Dérive la clé de chiffrement via PBKDF2(username + salt)
  /// Retourne : base64(salt[16] + iv[12] + ciphertext + tag[16])
  static String encryptFragment(String fragmentHex, String username) {
    try {
      final fragmentBytes = _hexToBytes(fragmentHex);
      final random = Random.secure();

      // Générer salt aléatoire (16 bytes)
      final salt = Uint8List(16);
      for (int i = 0; i < 16; i++) {
        salt[i] = random.nextInt(256);
      }

      // Dériver la clé AES-256 via PBKDF2
      final derivedKey = _deriveKey(username, salt);

      // Générer IV aléatoire (12 bytes pour GCM)
      final iv = Uint8List(12);
      for (int i = 0; i < 12; i++) {
        iv[i] = random.nextInt(256);
      }

      // Chiffrer avec AES-256-GCM
      final cipher = GCMBlockCipher(AESEngine());
      final params = AEADParameters(
        KeyParameter(derivedKey),
        128, // tag length in bits
        iv,
        Uint8List(0), // no AAD
      );
      cipher.init(true, params);

      final cipherText = Uint8List(cipher.getOutputSize(fragmentBytes.length));
      final len = cipher.processBytes(
          fragmentBytes, 0, fragmentBytes.length, cipherText, 0);
      cipher.doFinal(cipherText, len);

      // Combiner : salt + iv + ciphertext (inclut tag GCM)
      final result = Uint8List(salt.length + iv.length + cipherText.length);
      result.setRange(0, salt.length, salt);
      result.setRange(salt.length, salt.length + iv.length, iv);
      result.setRange(salt.length + iv.length, result.length, cipherText);

      print('[FRAGMENT] Fragment chiffré: ${result.length} bytes');
      return base64Encode(result);
    } catch (e) {
      print('[FRAGMENT] Erreur chiffrement: $e');
      rethrow;
    }
  }

  /// Déchiffrement AES-256-GCM d'un fragment
  ///
  /// Input : base64(salt[16] + iv[12] + ciphertext + tag[16])
  /// Retourne : fragment en hex
  static String decryptFragment(String encryptedBase64, String username) {
    try {
      final encryptedBytes = base64Decode(encryptedBase64);

      if (encryptedBytes.length < 28) {
        throw ArgumentError('Données chiffrées trop courtes');
      }

      // Extraire salt, iv, ciphertext
      final salt = Uint8List.fromList(encryptedBytes.sublist(0, 16));
      final iv = Uint8List.fromList(encryptedBytes.sublist(16, 28));
      final cipherText = Uint8List.fromList(encryptedBytes.sublist(28));

      // Dériver la clé AES-256 via PBKDF2
      final derivedKey = _deriveKey(username, salt);

      // Déchiffrer avec AES-256-GCM
      final cipher = GCMBlockCipher(AESEngine());
      final params = AEADParameters(
        KeyParameter(derivedKey),
        128,
        iv,
        Uint8List(0),
      );
      cipher.init(false, params);

      final plainText = Uint8List(cipher.getOutputSize(cipherText.length));
      final len =
          cipher.processBytes(cipherText, 0, cipherText.length, plainText, 0);
      cipher.doFinal(plainText, len);

      // Retirer les éventuels bytes de padding nuls
      int actualLen = plainText.length;
      while (actualLen > 0 && plainText[actualLen - 1] == 0) {
        actualLen--;
      }

      print('[FRAGMENT] Fragment déchiffré: $actualLen bytes');
      return _bytesToHex(Uint8List.fromList(plainText.sublist(0, actualLen)));
    } catch (e) {
      print('[FRAGMENT] Erreur déchiffrement: $e');
      rethrow;
    }
  }

  // ============================================================
  // Fonctions utilitaires privées
  // ============================================================

  /// Dérive une clé AES-256 via PBKDF2-HMAC-SHA256
  static Uint8List _deriveKey(String username, Uint8List salt) {
    final pbkdf2 = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64));
    pbkdf2.init(Pbkdf2Parameters(salt, 100000, 32));
    return pbkdf2.process(Uint8List.fromList(utf8.encode(username)));
  }

  /// Convertir hex string en bytes
  static Uint8List _hexToBytes(String hex) {
    final cleanHex = hex.replaceAll(' ', '');
    final result = Uint8List(cleanHex.length ~/ 2);
    for (int i = 0; i < result.length; i++) {
      result[i] = int.parse(cleanHex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return result;
  }

  /// Convertir bytes en hex string
  static String _bytesToHex(Uint8List bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}
