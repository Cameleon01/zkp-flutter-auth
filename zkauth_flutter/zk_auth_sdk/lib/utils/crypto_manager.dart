import 'dart:math';
import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:pointycastle/export.dart';
import '../models/models.dart';

/// Gestionnaire de cryptographie pour ZK-AUTH
/// Implémente le protocole de Schnorr sur courbe elliptique secp256k1
class CryptoManager {
  // ParamÃ¨tres de la courbe secp256k1
  static final ECDomainParameters _secp256k1 = ECDomainParameters('secp256k1');

  /// Générer une paire de Clés (privée, publique)
  KeyPair generateKeyPair() {
    try {
      print('ðŸ” [CryptoManager] Génération de la paire de Clés...');

      // Générer une Clé privée aléatoire
      final random = Random.secure();
      final privateKeyBytes = Uint8List(32);
      for (int i = 0; i < 32; i++) {
        privateKeyBytes[i] = random.nextInt(256);
      }

      // Convertir en BigInt
      final privateKeyInt = _bytesToBigInt(privateKeyBytes);

      // Calculer la Clé publique : Q = d * G
      final publicKeyPoint = (_secp256k1.G * privateKeyInt)!;

      // Encoder les Clés en hexadécimal
      final privateKeyHex = _bigIntToHex(privateKeyInt);
      final publicKeyHex = _pointToHex(publicKeyPoint);

      print(' [CryptoManager] Clés générées');
      print(
          'ðŸ”‘ [CryptoManager] Clé publique: ${publicKeyHex.substring(0, 20)}...');

      return KeyPair(
        privateKey: privateKeyHex,
        publicKey: publicKeyHex,
      );
    } catch (e) {
      print(' Erreur génération Clés: $e');
      rethrow;
    }
  }

  /// Générer une preuve Zero-Knowledge (Schnorr)
  ZKProof generateProof({
    required String privateKeyHex,
    required String challenge,
  }) {
    try {
      print('Génération de la preuve ZK...');

      // Convertir la Clé privée
      final privateKey = _hexToBigInt(privateKeyHex);

      // Générer un nonce aléatoire k
      final random = Random.secure();
      final k = _generateRandomBigInt(random);

      // Calculer r = k * G
      final rPoint = (_secp256k1.G * k)!;
      final r = _pointToHex(rPoint);

      // Calculer le challenge e = H(r || challenge)
      final e = _hashToChallenge(r + challenge);

      // Calculer s = k + e * privateKey (mod n)
      final s = (k + (e * privateKey)) % _secp256k1.n;
      final sHex = _bigIntToHex(s);

      print(' [CryptoManager] Preuve générée');

      return ZKProof(
        r: r,
        s: sHex,
        challenge: challenge,
      );
    } catch (e) {
      print('Erreur génération preuve: $e');
      rethrow;
    }
  }

  /// Vérifier une preuve Zero-Knowledge
  bool verifyProof({
    required String publicKeyHex,
    required ZKProof proof,
  }) {
    try {
      print('Vérification de la preuve...');

      // Convertir la Clé publique
      final publicKeyPoint = _hexToPoint(publicKeyHex);

      // Convertir s
      final s = _hexToBigInt(proof.s);

      // Convertir r
      final rPoint = _hexToPoint(proof.r);

      // Calculer le challenge
      final e = _hashToChallenge(proof.r + proof.challenge);

      // Vérifier : s * G = r + e * Q
      final leftSide = (_secp256k1.G * s)!;
      final rightSide = (rPoint + (publicKeyPoint * e)!)!;

      final isValid = leftSide == rightSide;

      print(isValid
          ? ' [CryptoManager] Preuve valide'
          : 'Vérifier[CryptoManager] Preuve invalide');

      return isValid;
    } catch (e) {
      print('Erreur vérification: $e');
      return false;
    }
  }

  // === Méthodes utilitaires ===

  BigInt _bytesToBigInt(Uint8List bytes) {
    BigInt result = BigInt.zero;
    for (int i = 0; i < bytes.length; i++) {
      result = (result << 8) | BigInt.from(bytes[i]);
    }
    return result;
  }

  String _bigIntToHex(BigInt value) {
    return value.toRadixString(16).padLeft(64, '0');
  }

  BigInt _hexToBigInt(String hex) {
    return BigInt.parse(hex, radix: 16);
  }

  String _pointToHex(ECPoint point) {
    final x = point.x!.toBigInteger()!;
    final y = point.y!.toBigInteger()!;
    return '04${_bigIntToHex(x)}${_bigIntToHex(y)}';
  }

  ECPoint _hexToPoint(String hex) {
    if (hex.startsWith('04')) {
      hex = hex.substring(2);
    }
    final x = _hexToBigInt(hex.substring(0, 64));
    final y = _hexToBigInt(hex.substring(64));
    return _secp256k1.curve.createPoint(x, y);
  }

  BigInt _generateRandomBigInt(Random random) {
    final bytes = Uint8List(32);
    for (int i = 0; i < 32; i++) {
      bytes[i] = random.nextInt(256);
    }
    return _bytesToBigInt(bytes) % _secp256k1.n;
  }

  BigInt _hashToChallenge(String message) {
    final bytes = utf8.encode(message);
    final digest = sha256.convert(bytes);
    return _bytesToBigInt(Uint8List.fromList(digest.bytes)) % _secp256k1.n;
  }

  /// Générer la clé publique depuis une clé privée
  String getPublicKeyFromPrivate(String privateKeyHex) {
    try {
      final privateKeyBytes = _hexToBytes(privateKeyHex);
      final privateKey = ECPrivateKey(privateKeyBytes as BigInt?, _secp256k1);

      // Calculer la clé publique (point sur la courbe)
      final publicKeyPoint = (_secp256k1.G * privateKey.d)!;

      // Encoder en format non compressé (04 + x + y)
      final publicKeyBytes = publicKeyPoint.getEncoded(false);

      return _bytesToHex(publicKeyBytes);
    } catch (e) {
      print('[CRYPTO] Erreur génération clé publique: $e');
      rethrow;
    }
  }

  /// Convertir hex en bytes
  Uint8List _hexToBytes(String hex) {
    final result = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < hex.length; i += 2) {
      result[i ~/ 2] = int.parse(hex.substring(i, i + 2), radix: 16);
    }
    return result;
  }

  /// Convertir bytes en hex
  String _bytesToHex(Uint8List bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join('');
  }
}
