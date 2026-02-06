"""
Cryptographic utilities for ZK-AUTH
Schnorr signature verification on secp256k1
"""
import hashlib
from ecdsa import SECP256k1, VerifyingKey, BadSignatureError
from ecdsa.ellipticcurve import Point


class SchnorrVerifier:
    """
    Verifies Schnorr signatures on secp256k1 elliptic curve
    """
    
    def __init__(self):
        self.curve = SECP256k1
        self.generator = self.curve.generator
        self.order = self.curve.order
    
    def verify_proof(self, public_key_hex, proof_data, challenge):
        """
        Verify a Schnorr Zero-Knowledge proof
        
        Args:
            public_key_hex (str): Public key in hex format (04 + x + y)
            proof_data (dict): Contains 'r', 's', 'challenge'
            challenge (str): Server-generated challenge
            
        Returns:
            bool: True if proof is valid, False otherwise
        """
        try:
            print(f"\n{'='*60}")
            print(f"SCHNORR VERIFICATION DEBUG")
            print(f"{'='*60}")
            
            # Extract proof components
            r_hex = proof_data.get('r')
            s_hex = proof_data.get('s')
            proof_challenge = proof_data.get('challenge')
            
            print(f"\n 1 PROOF COMPONENTS:")
            print(f"  r_hex length: {len(r_hex) if r_hex else 0}")
            print(f"  s_hex length: {len(s_hex) if s_hex else 0}")
            print(f"  r_hex (first 40): {r_hex[:40] if r_hex else None}...")
            print(f"  s_hex (first 40): {s_hex[:40] if s_hex else None}...")
            
            # Validate inputs
            if not all([r_hex, s_hex, proof_challenge, challenge]):
                print("Missing proof components")
                return False
            
            print(f"\n2ï¸ CHALLENGE VERIFICATION:")
            print(f"  Proof challenge: {proof_challenge[:40]}...")
            print(f"  Server challenge: {challenge[:40]}...")
            print(f"  Challenges match: {proof_challenge == challenge}")
            
            if proof_challenge != challenge:
                print("Challenge mismatch!")
                return False
            print("Challenges match")
            
            # Parse public key
            print(f"\n 3 PARSING PUBLIC KEY:")
            print(f"  Public key hex (first 40): {public_key_hex[:40]}...")
            public_key_point = self._parse_public_key(public_key_hex)
            if public_key_point is None:
                print("âŒ Invalid public key")
                return False
            print(f" Public key parsed successfully")
            print(f"  Q.x = {public_key_point.x()}")
            print(f"  Q.y = {public_key_point.y()}")
            
            # Parse r (commitment point)
            print(f"\n 4 PARSING COMMITMENT R:")
            r_point = self._parse_public_key(r_hex)
            if r_point is None:
                print("âŒ Invalid commitment point r")
                return False
            print(f" Commitment point r parsed")
            print(f"  r.x = {r_point.x()}")
            print(f"  r.y = {r_point.y()}")
            
            # Parse s (response scalar)
            print(f"\n 5 PARSING RESPONSE S:")
            s = int(s_hex, 16) % self.order
            print(f" Response s parsed")
            print(f"  s (decimal) = {s}")
            print(f"  s (hex) = {hex(s)}")
            
            # Compute challenge hash: e = H(r || challenge)
            print(f"\n 6 COMPUTING HASH e = H(r || challenge):")
            hash_input = r_hex + challenge
            print(f"  Hash input length: {len(hash_input)}")
            print(f"  Hash input (first 80): {hash_input[:80]}...")
            
            e = self._hash_to_scalar(hash_input)
            print(f"  Hash  ")
            print(f"  e (decimal) = {e}")
            print(f"  e (hex) = {hex(e)}")
            
            # Verify: s * G = r + e * Q
            print(f"\n 7 SCHNORR EQUATION: s*G = r + e*Q")
            
            # Left side: s * G
            print(f"\n  LEFT SIDE (s * G):")
            left_side = self.generator * s
            print(f"    s = {s}")
            print(f"    G.x = {self.generator.x()}")
            print(f"    G.y = {self.generator.y()}")
            print(f"    (s*G).x = {left_side.x()}")
            print(f"    (s*G).y = {left_side.y()}")
            
            # Right side: r + e * Q
            print(f"\n  RIGHT SIDE (r + e*Q):")
            e_Q = public_key_point * e
            print(f"    e = {e}")
            print(f"    Q.x = {public_key_point.x()}")
            print(f"    Q.y = {public_key_point.y()}")
            print(f"    (e*Q).x = {e_Q.x()}")
            print(f"    (e*Q).y = {e_Q.y()}")
            
            right_side = r_point + e_Q
            print(f"    r.x = {r_point.x()}")
            print(f"    r.y = {r_point.y()}")
            print(f"    (r + e*Q).x = {right_side.x()}")
            print(f"    (r + e*Q).y = {right_side.y()}")
            
            # Compare points
            print(f"\n 8 FINAL COMPARISON:")
            x_match = left_side.x() == right_side.x()
            y_match = left_side.y() == right_side.y()
            is_valid = x_match and y_match
            
            print(f"  Left.x  = {left_side.x()}")
            print(f"  Right.x = {right_side.x()}")
            print(f"  X coordinates match: {x_match}")
            print(f"")
            print(f"  Left.y  = {left_side.y()}")
            print(f"  Right.y = {right_side.y()}")
            print(f"  Y coordinates match: {y_match}")
            print(f"")
            print(f"{'='*60}")
            
            if is_valid:
                print("SCHNORR PROOF VERIFIED SUCCESSFULLY")
            else:
                print(" SCHNORR PROOF VERIFICATION FAILED")
            
            print(f"{'='*60}\n")
            
            return is_valid
            
        except Exception as e:
            print(f"\n EXCEPTION in verify_proof: {str(e)}")
            import traceback
            traceback.print_exc()
            return False
    
    def _parse_public_key(self, hex_key):
        """
        Parse a public key from hex format
        
        Args:
            hex_key (str): Public key in hex (with or without 04 prefix)
            
        Returns:
            Point: Elliptic curve point or None if invalid
        """
        try:
            # Remove 04 prefix if present
            if hex_key.startswith('04'):
                hex_key = hex_key[2:]
            
            # Each coordinate is 32 bytes = 64 hex characters
            if len(hex_key) != 128:
                print(f" Invalid key length: {len(hex_key)}, expected 128")
                return None
            
            # Parse x and y coordinates
            x_hex = hex_key[:64]
            y_hex = hex_key[64:]
            
            x = int(x_hex, 16)
            y = int(y_hex, 16)
            
            # Create point on curve
            point = Point(self.curve.curve, x, y, self.order)
            
            # Verify point is on curve
            if not self.curve.curve.contains_point(x, y):
                print("âŒ Point not on curve")
                return None
            
            return point
            
        except Exception as e:
            print(f"Error parsing public key: {str(e)}")
            return None
    
    def _hash_to_scalar(self, message):
        """
        Hash a message to a scalar value modulo curve order
        
        Args:
            message (str): Message to hash
            
        Returns:
            int: Scalar value
        """
        hash_bytes = hashlib.sha256(message.encode()).digest()
        hash_int = int.from_bytes(hash_bytes, 'big')
        return hash_int % self.order


def verify_schnorr_proof(public_key_hex, proof_data, challenge):
    """
    Convenience function to verify Schnorr proof
    
    Args:
        public_key_hex (str): Public key in hex
        proof_data (dict): Proof containing r, s, challenge
        challenge (str): Server challenge
        
    Returns:
        bool: True if valid, False otherwise
    """
    verifier = SchnorrVerifier()
    return verifier.verify_proof(public_key_hex, proof_data, challenge)


def validate_public_key(public_key_hex):
    """
    Validate that a public key is well-formed
    
    Args:
        public_key_hex (str): Public key in hex
        
    Returns:
        bool: True if valid, False otherwise
    """
    try:
        verifier = SchnorrVerifier()
        point = verifier._parse_public_key(public_key_hex)
        return point is not None
    except Exception:
        return False
