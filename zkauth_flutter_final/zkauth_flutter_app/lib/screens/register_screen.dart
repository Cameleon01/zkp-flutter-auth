import 'package:flutter/material.dart';
import 'package:zk_auth_sdk/zk_auth_sdk.dart';
import '../main.dart';
import 'enrollment_screen.dart';
import 'package:local_auth/local_auth.dart';
import 'package:flutter/services.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();

  bool _isRegistering = false;
  String? _errorMessage;

  @override
  void dispose() {
    _usernameController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    final username = _usernameController.text.trim();
    final email = _emailController.text.trim();

    if (username.isEmpty || email.isEmpty) {
      setState(() {
        _errorMessage = 'Username et Email sont requis';
      });
      return;
    }

    //  AJOUT : Authentification AVANT inscription
    setState(() {
      _isRegistering = true;
      _errorMessage = null;
    });

    try {
      // Demander authentification Android d'abord
      final localAuth = LocalAuthentication();

      final authenticated = await localAuth.authenticate(
        localizedReason: 'Authentifiez-vous pour créer votre compte',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: false,
        ),
      );

      if (!authenticated) {
        setState(() {
          _errorMessage = 'Authentification requise';
          _isRegistering = false;
        });
        return;
      }
    } on PlatformException catch (e) {
      setState(() {
        _errorMessage = 'Erreur authentification: ${e.message}';
        _isRegistering = false;
      });
      return;
    }

    try {
      print('[REGISTER] Inscription: $username');

      // Inscription (pas de password, Android gérera la sécurité)
      final result = await zkAuthClient.register(
        username: username,
        email: email,
        password: username, // Juste pour l'API, non utilisé réellement
      );

      if (mounted) {
        if (result.success) {
          print('[REGISTER] ✓ Inscription réussie');

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Inscription réussie'),
              backgroundColor: Colors.green,
            ),
          );

          // Aller directement à l'enrôlement
          // Android demandera automatiquement PIN/empreinte
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => EnrollmentScreen(username: username),
            ),
          );
        } else {
          setState(() {
            _errorMessage = result.error ?? 'Échec de l\'inscription';
          });
        }
      }
    } catch (e) {
      print('[REGISTER] ✗ Erreur: $e');
      setState(() {
        _errorMessage = 'Erreur: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isRegistering = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Créer un compte'),
        backgroundColor: const Color(0xFFFF6B00),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 40),

              // Logo
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF6B00).withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.person_add,
                  size: 60,
                  color: Color(0xFFFF6B00),
                ),
              ),

              const SizedBox(height: 32),

              const Text(
                'Inscription',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFFFF6B00),
                ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 8),

              const Text(
                'Authentification Zero-Knowledge',
                style: TextStyle(fontSize: 14, color: Colors.grey),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 40),

              // Username
              TextField(
                controller: _usernameController,
                decoration: const InputDecoration(
                  labelText: 'Nom d\'utilisateur',
                  prefixIcon: Icon(Icons.person),
                  border: OutlineInputBorder(),
                ),
                enabled: !_isRegistering,
              ),

              const SizedBox(height: 16),

              // Email
              TextField(
                controller: _emailController,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  prefixIcon: Icon(Icons.email),
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.emailAddress,
                enabled: !_isRegistering,
              ),

              const SizedBox(height: 24),

              // Message d'erreur
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

              // Bouton inscription
              ElevatedButton(
                onPressed: _isRegistering ? null : _register,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF6B00),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: _isRegistering
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        'Créer mon compte',
                        style: TextStyle(fontSize: 16),
                      ),
              ),

              const SizedBox(height: 24),

              // Info sécurité
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Column(
                  children: const [
                    Icon(Icons.info_outline, color: Colors.blue),
                    SizedBox(height: 12),
                    Text(
                      'Votre sécurité sera gérée par votre téléphone',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Android vous demandera automatiquement votre empreinte, Face ID ou code PIN lors de l\'enrôlement',
                      style: TextStyle(fontSize: 12),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
