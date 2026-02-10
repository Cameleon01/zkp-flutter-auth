"""
Crypto utilities for ZK-AUTH - VERSION CORRIGEE
Correction 4.3(e) : Suppression de TOUS les print() de debug
qui exposaient les coordonnees des points dans la console.
"""
import hashlib
import logging
from ecdsa import SECP256k1, VerifyingKey, BadSignatureError
from ecdsa.ellipticcurve import Point

logger = logging.getLogger('authentication')

# secp256k1 curve parameters
CURVE = SECP256k1
GENERATOR = CURVE.generator
ORDER = CURVE.order


def validate_public_key(public_key_hex: str) -> bool:
    """
    Validate that a hex string is a valid secp256k1 public key.
    Accepts both compressed (02/03 prefix) and uncompressed (04 prefix) formats.
    """
    try:
        key = public_key_hex.strip()

        if key.startswith('04'):
            # Uncompressed: 04 + 64 hex X + 64 hex Y = 130 chars
            if len(key) != 130:
                return False
            x_hex = key[2:66]
            y_hex = key[66:130]
            x = int(x_hex, 16)
            y = int(y_hex, 16)

            # Verify point is on curve
            point = Point(CURVE.curve, x, y)
            # If Point() doesn't raise, the point is on the curve
            return True

        elif key.startswith('02') or key.startswith('03'):
            # Compressed: 02/03 + 64 hex X = 66 chars
            if len(key) != 66:
                return False
            int(key[2:], 16)  # Validate hex
            return True

        else:
            return False

    except Exception:
        return False


def hex_to_point(public_key_hex: str) -> Point:
    """
    Convert a hex public key to an elliptic curve point.
    Supports both compressed and uncompressed formats.
    """
    key = public_key_hex.strip()

    if key.startswith('04'):
        x = int(key[2:66], 16)
        y = int(key[66:130], 16)
        return Point(CURVE.curve, x, y)
    elif key.startswith('02') or key.startswith('03'):
        # Decompress
        vk = VerifyingKey.from_string(
            bytes.fromhex(key),
            curve=SECP256k1
        )
        point = vk.pubkey.point
        return Point(CURVE.curve, point.x(), point.y())
    else:
        raise ValueError("Invalid public key format")


def verify_schnorr_proof(
    public_key_hex: str,
    r_hex: str,
    s_hex: str,
    challenge_hex: str
) -> bool:
    """
    Verify a Schnorr zero-knowledge proof.

    Protocol (matching Flutter CryptoManager):
      1. Prover generates random k, computes R = k*G
      2. Prover computes e = H(R || challenge)   [no Q in hash]
      3. Prover computes s = k + e * private_key (mod n)
      4. Verifier checks: s*G == R + e*Q

    Args:
        public_key_hex: Public key Q in hex (compressed or uncompressed)
        r_hex: Commitment point R as hex (uncompressed 04...)
        s_hex: Response scalar s as hex
        challenge_hex: Challenge nonce as hex

    Returns:
        True if the proof is valid, False otherwise
    """
    try:
        # Parse public key point Q
        Q = hex_to_point(public_key_hex)

        # Parse commitment point R
        R = hex_to_point(r_hex)

        # Parse response scalar s
        s = int(s_hex, 16)

        # Compute challenge hash e = H(R || challenge)
        # Must match Flutter client: _hashToChallenge(r + challenge)
        # The client does NOT include public key Q in the hash
        hash_input = (r_hex + challenge_hex).encode('utf-8')
        e_hash = hashlib.sha256(hash_input).digest()
        e = int.from_bytes(e_hash, 'big') % ORDER

        # Verify: s*G == R + e*Q
        # Because client computes s = k + e*privateKey (mod n)
        # So s*G = (k + e*x)*G = k*G + e*x*G = R + e*Q
        sG = GENERATOR * s
        eQ = Q * e
        rhs = R + eQ  # R + e*Q

        if sG.x() == rhs.x() and sG.y() == rhs.y():
            logger.info("Schnorr proof verification: SUCCESS")
            return True
        else:
            logger.warning("Schnorr proof verification: FAILED (point mismatch)")
            return False

    except Exception as e:
        logger.error(f"Schnorr verification error: {type(e).__name__}")
        return False
