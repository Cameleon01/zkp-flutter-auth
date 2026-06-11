/// Fragment Manager - NOUVEAU FICHIER
/// Corrections audit :
///   4.1.1 : Fragmentation cryptographique XOR (remplace le split string naif)
///   4.1.2 : Chiffrement AES-256-GCM des fragments avant transmission
///
/// AVANT (VULNERABLE) :
///   fragmentA = privateKeyHex.substring(0, mid)
///   fragmentB = privateKeyHex.substring(mid)
///   -> Chaque fragment revele la moitie de la cle en clair
///
/// APRES (SECURISE) :
///   fragmentA = random bytes de meme taille que la cle
///   fragmentB = cle XOR fragmentA
///   -> Aucun fragment ne revele quoi que ce soit sans l'autre
///
/// Emplacement : lib/services/fragment_manager.dart
library;

import 'dart:convert';
import 'dart:typed_data';
import 'package:pointycastle/export.dart';
import 'dart:math';

class FragmentManager {
  /// Fragmentation cryptographique XOR
  /// Retourne {fragmentA: hex, fragmentB: hex}
  ///
  /// Principe : fragmentA est aleatoire, fragmentB = cle XOR fragmentA
  /// Reconstruction : cle = fragmentA XOR fragmentB
  static Map<String, String> fragmentKey(String privateKeyHex) {
    final keyBytes = _hexToBytes(privateKeyHex);

    // Generer Fragment A : bytes aleatoires de meme taille
    final secureRandom = FortunaRandom();
    final seed = Uint8List(32);
    final dartRandom = Random.secure();
    for (int i = 0; i < seed.length; i++) {
      seed[i] = dartRandom.nextInt(256);
    }
    secureRandom.seed(KeyParameter(seed));

    final fragmentA = secureRandom.nextBytes(keyBytes.length);

    // Fragment B = cle XOR Fragment A
    final fragmentB = Uint8List(keyBytes.length);
    for (int i = 0; i < keyBytes.length; i++) {
      fragmentB[i] = keyBytes[i] ^ fragmentA[i];
    }

    return {
      'fragmentA': _bytesToHex(fragmentA),
      'fragmentB': _bytesToHex(fragmentB),
    };
  }

  /// Reconstruction de la cle depuis les deux fragments
  /// cle = fragmentA XOR fragmentB
  static String reconstructKey(String fragmentAHex, String fragmentBHex) {
    final fragmentA = _hexToBytes(fragmentAHex);
    final fragmentB = _hexToBytes(fragmentBHex);

    if (fragmentA.length != fragmentB.length) {
      throw ArgumentError('Fragments de tailles differentes');
    }

    final keyBytes = Uint8List(fragmentA.length);
    for (int i = 0; i < fragmentA.length; i++) {
      keyBytes[i] = fragmentA[i] ^ fragmentB[i];
    }

    return _bytesToHex(keyBytes);
  }

  /// Chiffrement AES-256-GCM d'un fragment avant transmission
  ///
  /// Derive la cle de chiffrement via PBKDF2(username + salt)
  /// Retourne : base64(salt[16] + iv[12] + ciphertext + tag[16])
  static String encryptFragment(String fragmentHex, String username) {
    final fragmentBytes = _hexToBytes(fragmentHex);

    // Generer un salt aleatoire (16 bytes)
    final secureRandom = FortunaRandom();
    final seed = Uint8List(32);
    final dartRandom = Random.secure();
    for (int i = 0; i < seed.length; i++) {
      seed[i] = dartRandom.nextInt(256);
    }
    secureRandom.seed(KeyParameter(seed));

    final salt = secureRandom.nextBytes(16);

    // Deriver la cle via PBKDF2
    final derivedKey = _deriveKey(username, salt);

    // Generer IV aleatoire (12 bytes pour GCM)
    final iv = secureRandom.nextBytes(12);

    // Chiffrer avec AES-256-GCM
    final cipher = GCMBlockCipher(AESEngine());
    final params = AEADParameters(
      KeyParameter(derivedKey),
      128, // tag length in bits
      iv,
      Uint8List(0), // no AAD
    );
    cipher.init(true, params);

    final cipherText = Uint8List(
        cipher.getOutputSize(fragmentBytes.length));
    final len = cipher.processBytes(
        fragmentBytes, 0, fragmentBytes.length, cipherText, 0);
    cipher.doFinal(cipherText, len);

    // Combiner : salt + iv + ciphertext (inclut tag)
    final result = Uint8List(salt.length + iv.length + cipherText.length);
    result.setRange(0, salt.length, salt);
    result.setRange(salt.length, salt.length + iv.length, iv);
    result.setRange(salt.length + iv.length, result.length, cipherText);

    return base64Encode(result);
  }

  /// Dechiffrement AES-256-GCM d'un fragment
  ///
  /// Input : base64(salt[16] + iv[12] + ciphertext + tag[16])
  /// Retourne : fragment en hex
  static String decryptFragment(String encryptedBase64, String username) {
    final encryptedBytes = base64Decode(encryptedBase64);

    if (encryptedBytes.length < 28) {
      // Minimum: 16 salt + 12 iv = 28 bytes header
      throw ArgumentError('Donnees chiffrees trop courtes');
    }

    // Extraire salt, iv, ciphertext
    final salt = Uint8List.fromList(encryptedBytes.sublist(0, 16));
    final iv = Uint8List.fromList(encryptedBytes.sublist(16, 28));
    final cipherText =
        Uint8List.fromList(encryptedBytes.sublist(28));

    // Deriver la cle via PBKDF2
    final derivedKey = _deriveKey(username, salt);

    // Dechiffrer avec AES-256-GCM
    final cipher = GCMBlockCipher(AESEngine());
    final params = AEADParameters(
      KeyParameter(derivedKey),
      128, // tag length in bits
      iv,
      Uint8List(0), // no AAD
    );
    cipher.init(false, params);

    final plainText = Uint8List(
        cipher.getOutputSize(cipherText.length));
    final len = cipher.processBytes(
        cipherText, 0, cipherText.length, plainText, 0);
    cipher.doFinal(plainText, len);

    // Trim padding zeros
    int actualLen = plainText.length;
    while (actualLen > 0 && plainText[actualLen - 1] == 0) {
      actualLen--;
    }

    return _bytesToHex(Uint8List.fromList(plainText.sublist(0, actualLen)));
  }

  // ============================================================
  // Fonctions utilitaires privees
  // ============================================================

  /// Derive une cle AES-256 via PBKDF2
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
