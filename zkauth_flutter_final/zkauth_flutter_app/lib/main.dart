import 'package:flutter/material.dart';
import 'package:zk_auth_sdk/zk_auth_sdk.dart';

import 'screens/splash_screen.dart';
import 'screens/login_screen.dart';
import 'screens/register_screen.dart';
import 'screens/enrollment_screen.dart';
import 'screens/home_screen.dart';
import 'screens/backup_screen.dart';
import 'screens/restore_screen.dart';

void main() {
  runApp(const MyMomoApp());
}

/// Instance globale du client ZK-AUTH
/// ⚠️ À configurer avec l'URL de votre backend
final zkAuthClient = ZKAuthClient(
  //baseUrl: 'http://10.64.10.211:8000', //
  // baseUrl: 'http://10.231.72.80:8000', //
  baseUrl: 'http://192.168.100.6:8000', //
  // baseUrl: 'http://172.25.215.80:8000', //
);

class MyMomoApp extends StatelessWidget {
  const MyMomoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MyMomo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.orange,
        primaryColor: const Color(0xFFFF6B00),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFFF6B00),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(centerTitle: true, elevation: 0),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 32),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ),
      home: const LoginScreen(),
      routes: {
        '/login': (context) => const LoginScreen(),
        '/register': (context) => const RegisterScreen(),
        '/home': (context) => const HomeScreen(),
        '/backup': (context) => const BackupScreen(username: ''),
      },
    );
  }
}
