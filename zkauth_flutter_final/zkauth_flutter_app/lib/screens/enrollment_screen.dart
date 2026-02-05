import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:zk_auth_sdk/zk_auth_sdk.dart';
import '../main.dart';
import 'home_screen.dart';
import 'backup_screen.dart';

class EnrollmentScreen extends StatefulWidget {
  final String username;

  const EnrollmentScreen({super.key, required this.username});

  @override
  State<EnrollmentScreen> createState() => _EnrollmentScreenState();
}

class _EnrollmentScreenState extends State<EnrollmentScreen> {
  bool _isLoading = false;
  String? _errorMessage;

  /* Future<void> _enrollUser() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      print('[EnrollmentScreen] Début enrôlement pour: ${widget.username}');

      // Appel SDK
      final result = await zkAuthClient.enroll(widget.username);

      print('Résultat enrôlement: ${result.success}');
      print('Message: ${result.message}');
      print('Erreur: ${result.error}');

      if (result.success) {
        print('[EnrollmentScreen] Enrôlement réussi!');

        if (mounted) {
          // Afficher dialog de succès
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (context) => AlertDialog(
              title: const Text('Enrôlement Réussi!'),
              content: const Text(
                'Votre clé privée a été générée et stockée localement.\n\n'
                'Voulez-vous sauvegarder votre clé de restauration?',
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                    // Aller directement au HomeScreen
                    Navigator.pushReplacementNamed(context, '/home');
                  },
                  child: const Text('Plus tard'),
                ),
                ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    // Aller au BackupScreen
                    Navigator.pushNamed(context, '/backup');
                  },
                  child: const Text('Sauvegarder'),
                ),
              ],
            ),
          );
        }
      } else {
        // Erreur
        setState(() {
          _errorMessage = result.error ?? 'Échec de l\'enrôlement';
        });
        print('Échec: $_errorMessage');

        // Afficher l'erreur à l'utilisateur
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Erreur: $_errorMessage'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 5),
            ),
          );
        }
      }
    } catch (e, stackTrace) {
      setState(() {
        _errorMessage = 'Exception: $e';
      });
      print('Exception: $e');
      print('Stack trace: $stackTrace');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur technique: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }
 */

  Future<void> _enrollUser() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      print(' [EnrollmentScreen] Début enrôlement pour: ${widget.username}');

      //  ÉTAPE 1 : BIOMÉTRIE LOCALE D'ABORD
      final localAuth = LocalAuthentication();

      try {
        final canCheck = await localAuth.canCheckBiometrics;
        final isSupported = await localAuth.isDeviceSupported();

        if (canCheck && isSupported) {
          print(' Demande biométrie avant génération clé...');

          final authenticated = await localAuth.authenticate(
            localizedReason:
                'Authentifiez-vous pour générer votre clé sécurisée',
            options: const AuthenticationOptions(
              stickyAuth: true,
              biometricOnly: false,
              useErrorDialogs: true,
            ),
          );

          if (!authenticated) {
            setState(() {
              _errorMessage = 'Authentification biométrique requise';
              _isLoading = false;
            });
            return;
          }

          print(' Biométrie validée, génération de la clé...');
        } else {
          print('⚠️ Biométrie non disponible, continuer sans');
        }
      } on PlatformException catch (e) {
        print('⚠️ Erreur biométrie: ${e.code}, continuer quand même');
        // On continue même si biométrie échoue
      }

      //  ÉTAPE 2 : Génération clé (après biométrie)
      final result = await zkAuthClient.enroll(widget.username);

      if (result.success) {
        print(' [EnrollmentScreen] Enrôlement réussi!');

        if (mounted) {
          _showBackupDialog();
        }
      } else {
        setState(() {
          _errorMessage = result.error ?? 'Échec de l\'enrôlement';
        });
        print(' Échec: $_errorMessage');
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Erreur: $e';
      });
      print(' Exception: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _showBackupDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Enrollement Réussi!'),
        content: const Text(
          'Voulez-vous sauvegarder votre Clé de restauration?\n\n'
          'Cette sauvegarde vous permettra de recuperer votre compte '
          'si vous perdez votre téléphone.',
        ),
        actions: [
          // TextButton(
          //   onPressed: () {
          //     Navigator.pop(context);
          //     Navigator.pushReplacement(
          //       context,
          //       MaterialPageRoute(builder: (_) => const HomeScreen()),
          //     );
          //   },
          //   child: const Text('Plus tard'),
          // ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => BackupScreen(username: widget.username),
                ),
              ).then((_) {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (_) => const HomeScreen()),
                );
              });
            },
            child: const Text('Sauvegarder'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Configuration ZK-AUTH')),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.fingerprint, size: 120, color: Color(0xFFFF6B00)),
            const SizedBox(height: 32),

            const Text(
              'Authentification Sécurisée',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),

            Text(
              'Utilisateur: ${widget.username}',
              style: const TextStyle(
                fontSize: 16,
                color: Colors.grey,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),

            const Text(
              'Nous allons configurer une authentification '
              'Zero-Knowledge qui protègera votre compte contre '
              'les pirates.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 32),

            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildStepInfo('1', 'Génération Clé privée', Icons.key),
                  const SizedBox(height: 8),
                  _buildStepInfo('2', 'Protection locale', Icons.security),
                  const SizedBox(height: 8),
                  _buildStepInfo(
                    '3',
                    'Enregistrement serveur',
                    Icons.cloud_upload,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),

            if (_errorMessage != null)
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline, color: Colors.red.shade700),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: TextStyle(color: Colors.red.shade900),
                      ),
                    ),
                  ],
                ),
              ),

            ElevatedButton(
              onPressed: _isLoading ? null : _enrollUser,
              child: _isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Text('Configurer maintenant'),
            ),
            const SizedBox(height: 16),

            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.security, color: Colors.green.shade700),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Votre Clé privée ne quittera jamais votre appareil',
                      style: TextStyle(
                        color: Colors.green.shade900,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStepInfo(String number, String text, IconData icon) {
    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: Colors.blue.shade700,
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              number,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Icon(icon, size: 20, color: Colors.blue.shade700),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(color: Colors.blue.shade900, fontSize: 13),
          ),
        ),
      ],
    );
  }
}
