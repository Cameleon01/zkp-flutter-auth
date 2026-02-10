import 'package:flutter/material.dart';
import 'package:zk_auth_sdk/zk_auth_sdk.dart';
import '../main.dart';

/// Écran de restauration - VERSION CORRIGÉE AUDIT
///
/// CORRECTIONS :
///   - Le flux complet (déchiffrement + reconstruction + re-enrôlement)
///     est maintenant dans zkAuthClient.restoreFromGoogleDrive()
///   - Plus besoin d'appeler enrollWithBiometrics() séparément
///   - Suppression du TODO placeholder + Future.delayed(2s)
///
/// Emplacement : zkauth_flutter_app/lib/screens/restore_screen.dart
class RestoreScreen extends StatefulWidget {
  const RestoreScreen({super.key});

  @override
  State<RestoreScreen> createState() => _RestoreScreenState();
}

class _RestoreScreenState extends State<RestoreScreen> {
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;
  String? _successMessage;
  int _currentStep = 0; // Pour le stepper visuel

  @override
  void dispose() {
    _usernameController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _startRestore() async {
    if (_usernameController.text.isEmpty || _emailController.text.isEmpty) {
      setState(() {
        _errorMessage = 'Tous les champs sont requis';
        _successMessage = null;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _successMessage = null;
      _currentStep = 0;
    });

    try {
      final username = _usernameController.text.trim();
      final email = _emailController.text.trim();

      print('[RESTORE] Début restauration pour: $username');

      // =============================================
      // ÉTAPE 1 : Vérifier username/email
      // =============================================
      setState(() {
        _currentStep = 1;
        _successMessage = 'Vérification des identifiants...';
      });

      final verificationResult = await zkAuthClient.verifyUserCredentials(
        username: username,
        email: email,
      );

      if (!verificationResult) {
        setState(() {
          _errorMessage = 'Username ou email incorrect';
          _isLoading = false;
        });
        return;
      }

      print('[RESTORE] ✓ Identifiants valides');

      // =============================================
      // ÉTAPE 2 : Restauration complète via le SDK
      //   - Récupère Fragment A (Drive) + Fragment B (serveur)
      //   - Déchiffre les fragments (AES-256-GCM)
      //   - Reconstruit la clé (XOR)
      //   - Génère nouvelle paire de clés
      //   - Re-enrôlement avec nouvelle clé publique
      // =============================================
      setState(() {
        _currentStep = 2;
        _successMessage = 'Récupération et déchiffrement des fragments...';
      });

      final result = await zkAuthClient.restoreFromGoogleDrive(
        username: username,
        email: email,
      );

      if (!result.success) {
        setState(() {
          _errorMessage = result.error ?? 'Erreur lors de la restauration';
          _isLoading = false;
        });
        return;
      }

      // =============================================
      // ÉTAPE 3 : Succès
      // =============================================
      setState(() {
        _currentStep = 3;
        _successMessage = 'Compte restauré avec succès !';
      });

      print('[RESTORE] ✓ Restauration complète réussie');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Restauration complète réussie'),
            backgroundColor: Colors.green,
          ),
        );

        await Future.delayed(const Duration(seconds: 2));

        if (mounted) {
          Navigator.pushNamedAndRemoveUntil(
            context,
            '/login',
            (route) => false,
          );
        }
      }
    } catch (e) {
      print('[RESTORE] ❌ Exception: $e');
      setState(() {
        _errorMessage = 'Erreur: $e';
        _isLoading = false;
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isComplete =
        _successMessage != null && !_successMessage!.contains('...');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Restaurer compte'),
        backgroundColor: const Color(0xFFFF6B00),
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Icône d'en-tête
              Icon(
                isComplete ? Icons.cloud_done : Icons.restore,
                size: 80,
                color: isComplete ? Colors.green : const Color(0xFFFF6B00),
              ),
              const SizedBox(height: 24),

              Text(
                isComplete ? 'Restauration réussie' : 'Restaurer votre compte',
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),

              // Formulaire (visible tant que pas terminé)
              if (!isComplete) ...[
                const Text(
                  'Entrez vos identifiants pour récupérer votre compte '
                  'depuis la sauvegarde chiffrée.',
                  style: TextStyle(fontSize: 14, color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),

                TextField(
                  controller: _usernameController,
                  decoration: const InputDecoration(
                    labelText: 'Nom d\'utilisateur',
                    prefixIcon: Icon(Icons.person),
                    border: OutlineInputBorder(),
                  ),
                  enabled: !_isLoading,
                ),
                const SizedBox(height: 16),

                TextField(
                  controller: _emailController,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    prefixIcon: Icon(Icons.email),
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.emailAddress,
                  enabled: !_isLoading,
                ),
                const SizedBox(height: 24),

                // Info processus
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            color: Colors.blue,
                            size: 20,
                          ),
                          SizedBox(width: 8),
                          Text(
                            'Processus de restauration',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 8),
                      Text(
                        '1. Vérification de vos identifiants\n'
                        '2. Récupération Fragment A (Google Drive)\n'
                        '3. Récupération Fragment B (Serveur)\n'
                        '4. Déchiffrement AES-256-GCM\n'
                        '5. Reconstruction clé par XOR\n'
                        '6. Génération nouvelle paire de clés\n'
                        '7. Re-enrôlement sécurisé',
                        style: TextStyle(fontSize: 12, height: 1.5),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
              ],

              // Stepper de progression (visible pendant le chargement)
              if (_isLoading || isComplete) _buildProgressStepper(),

              const SizedBox(height: 16),

              // Message d'erreur
              if (_errorMessage != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error, color: Colors.red),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: TextStyle(color: Colors.red.shade900),
                        ),
                      ),
                    ],
                  ),
                ),

              // Message de succès en cours
              if (_successMessage != null && _successMessage!.contains('...'))
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: Row(
                    children: [
                      const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _successMessage!,
                          style: TextStyle(color: Colors.blue.shade900),
                        ),
                      ),
                    ],
                  ),
                ),

              // Succès final
              if (isComplete)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.green.shade200),
                  ),
                  child: Column(
                    children: [
                      const Icon(
                        Icons.check_circle,
                        color: Colors.green,
                        size: 40,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _successMessage!,
                        style: TextStyle(
                          color: Colors.green.shade900,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),

              const SizedBox(height: 24),

              // Bouton restaurer
              if (!isComplete)
                ElevatedButton(
                  onPressed: _isLoading ? null : _startRestore,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF6B00),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Restaurer mon compte',
                          style: TextStyle(fontSize: 16),
                        ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Widget stepper de progression
  Widget _buildProgressStepper() {
    final steps = [
      'Vérification identifiants',
      'Récupération + déchiffrement',
      'Restauration complète',
    ];

    return Column(
      children: List.generate(steps.length, (index) {
        final stepNum = index + 1;
        final isDone = _currentStep > stepNum;
        final isCurrent = _currentStep == stepNum;

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isDone
                      ? Colors.green
                      : isCurrent
                      ? const Color(0xFFFF6B00)
                      : Colors.grey.shade300,
                ),
                child: Center(
                  child: isDone
                      ? const Icon(Icons.check, color: Colors.white, size: 16)
                      : Text(
                          '$stepNum',
                          style: TextStyle(
                            color: isCurrent
                                ? Colors.white
                                : Colors.grey.shade600,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  steps[index],
                  style: TextStyle(
                    color: isDone || isCurrent
                        ? Colors.black87
                        : Colors.grey.shade500,
                    fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ),
              if (isCurrent)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
        );
      }),
    );
  }
}
