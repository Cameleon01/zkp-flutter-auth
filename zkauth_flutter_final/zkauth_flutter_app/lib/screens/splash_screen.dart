/// Splash Screen - VERSION CORRIGEE
/// Correction audit bug 8 : Ne redirige plus vers HomeScreen sans
/// re-authentification biometrique. Un appareil deverrouille ne donne
/// plus acces direct a l'app.
///
/// Emplacement : lib/screens/splash_screen.dart
library;

import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import '../config/zkauth_config.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  final LocalAuthentication _localAuth = LocalAuthentication();

  @override
  void initState() {
    super.initState();
    _checkStatusAndRedirect();
  }

  Future<void> _checkStatusAndRedirect() async {
    await Future.delayed(const Duration(seconds: 2));

    if (!mounted) return;

    // Verifier si l'utilisateur est enrole
    // (votre logique existante pour verifier le statut)
    final isEnrolled = await _checkEnrollmentStatus();

    if (isEnrolled) {
      // CORRECTION bug 8 : Exiger re-authentification biometrique
      // AVANT : Redirigeait directement vers HomeScreen
      // APRES : Demande biometrie/PIN meme si l'appareil est deverrouille
      final authenticated = await _requireBiometricAuth();

      if (authenticated && mounted) {
        Navigator.pushReplacementNamed(context, '/home');
      } else if (mounted) {
        // Echec biometrie -> ecran de login
        Navigator.pushReplacementNamed(context, '/login');
      }
    } else {
      if (mounted) {
        Navigator.pushReplacementNamed(context, '/login');
      }
    }
  }

  /// CORRECTION : Re-authentification biometrique obligatoire
  Future<bool> _requireBiometricAuth() async {
    try {
      final bool canAuthenticate = await _localAuth.canCheckBiometrics ||
          await _localAuth.isDeviceSupported();

      if (!canAuthenticate) {
        // Pas de biometrie disponible -> rediriger vers login ZKP
        return false;
      }

      return await _localAuth.authenticate(
        localizedReason: 'Veuillez vous identifier pour acceder a ZK-AUTH',
        options: const AuthenticationOptions(
          biometricOnly: false, // Permet PIN comme fallback
          stickyAuth: true,
        ),
      );
    } catch (e) {
      return false;
    }
  }

  /// Verifier le statut d'enrolement (placeholder)
  Future<bool> _checkEnrollmentStatus() async {
    // TODO: Implementer avec votre SecureStorageManager
    // Verifier si une cle privee existe localement
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFF6B00),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.security,
              size: 80,
              color: Colors.white,
            ),
            const SizedBox(height: 24),
            const Text(
              'ZK-AUTH',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Authentification Zero-Knowledge',
              style: TextStyle(
                fontSize: 14,
                color: Colors.white70,
              ),
            ),
            const SizedBox(height: 48),
            const CircularProgressIndicator(
              color: Colors.white,
            ),
          ],
        ),
      ),
    );
  }
}
