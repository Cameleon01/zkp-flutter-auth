import 'package:flutter/material.dart';
import 'package:zk_auth_sdk/zk_auth_sdk.dart';
import '../main.dart';

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
    });

    try {
      final username = _usernameController.text.trim();
      final email = _emailController.text.trim();

      print('[RESTORE] Début restauration pour: $username');

      // ✅ ÉTAPE 1 : Vérifier username/email AVANT biométrie
      setState(() {
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

      // ✅ ÉTAPE 2 : Récupération fragments (avec affichage console)
      setState(() {
        _successMessage = 'Récupération des fragments...';
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

      print('[RESTORE] ✓ Fragments récupérés et validés');

      // ✅ ÉTAPE 3 : Génération nouvelle paire de clés
      setState(() {
        _successMessage = 'Génération nouvelle paire de clés...';
      });

      print('[RESTORE] Génération nouvelle paire de clés');

      final enrollResult = await zkAuthClient.enrollWithBiometrics(username);

      if (!enrollResult.success) {
        throw Exception(enrollResult.error ?? 'Échec génération nouvelle clé');
      }

      print('[RESTORE] ✓ Nouvelle paire de clés générée et enrôlée');

      setState(() {
        _successMessage = 'Compte restauré avec succès';
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Restauration complète réussie'),
            backgroundColor: Colors.green,
          ),
        );

        await Future.delayed(const Duration(seconds: 2));

        if (mounted) {
          Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
        }
      }
    } catch (e) {
      print('[RESTORE] Exception: $e');
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Restaurer compte'),
        backgroundColor: const Color(0xFFFF6B00),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(
                _successMessage != null && !_successMessage!.contains('cours')
                    ? Icons.cloud_done
                    : Icons.restore,
                size: 80,
                color:
                    _successMessage != null &&
                        !_successMessage!.contains('cours')
                    ? Colors.green
                    : const Color(0xFFFF6B00),
              ),
              const SizedBox(height: 24),

              Text(
                _successMessage != null && !_successMessage!.contains('cours')
                    ? 'Restauration réussie'
                    : 'Restaurer votre compte',
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),

              if (_successMessage == null ||
                  _successMessage!.contains('cours')) ...[
                const Text(
                  'Entrez vos identifiants pour récupérer votre compte depuis la sauvegarde chiffrée.',
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

                // Informations sur le processus
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
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
                        '1. Récupération Fragment A (Google Drive)',
                        style: TextStyle(fontSize: 12),
                      ),
                      SizedBox(height: 4),
                      Text(
                        '2. Récupération Fragment B (Serveur)',
                        style: TextStyle(fontSize: 12),
                      ),
                      SizedBox(height: 4),
                      Text(
                        '3. Reconstitution de votre clé',
                        style: TextStyle(fontSize: 12),
                      ),
                      SizedBox(height: 4),
                      Text(
                        '4. Ré-enrôlement sur ce device',
                        style: TextStyle(fontSize: 12),
                      ),
                      SizedBox(height: 4),
                      Text(
                        '5. Destruction ancienne clé',
                        style: TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 24),

              // Message d'erreur
              if (_errorMessage != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 24),
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

              // Message de succès/progression
              if (_successMessage != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 24),
                  decoration: BoxDecoration(
                    color: _successMessage!.contains('cours')
                        ? Colors.blue.shade50
                        : Colors.green.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: _successMessage!.contains('cours')
                          ? Colors.blue.shade200
                          : Colors.green.shade200,
                    ),
                  ),
                  child: Row(
                    children: [
                      _successMessage!.contains('cours')
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.check_circle, color: Colors.green),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _successMessage!,
                          style: TextStyle(
                            color: _successMessage!.contains('cours')
                                ? Colors.blue.shade900
                                : Colors.green.shade900,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

              // Bouton restaurer
              if (_successMessage == null || _successMessage!.contains('cours'))
                ElevatedButton(
                  onPressed: _isLoading ? null : _startRestore,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF6B00),
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
}
