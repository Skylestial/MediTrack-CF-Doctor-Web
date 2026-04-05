import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_options.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'screens/dashboard_screen.dart';
import 'screens/login_screen.dart';
import 'providers/theme_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    // Disable persistence to prevent stale cached data
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: false,
    );
  } catch (_) {
    // Continue running app even if Firebase fails, for UI demo purposes
  } 
  runApp(const DoctorApp());
}

class DoctorApp extends StatelessWidget {
  const DoctorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => ThemeProvider(),
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, child) {
          return MaterialApp(
            title: 'MediTrack CF Doctor',
            debugShowCheckedModeBanner: false,
            themeMode: themeProvider.themeMode,
            theme: _buildTheme(Brightness.light),
            darkTheme: _buildTheme(Brightness.dark),
            home: StreamBuilder(
            stream: FirebaseAuth.instance.authStateChanges(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                final isDark = themeProvider.isDarkMode;
                return Scaffold(
                  backgroundColor: isDark ? const Color(0xFF111827) : Colors.white,
                  body: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Image.asset('assets/logo.png', height: 80, width: 80),
                        const SizedBox(height: 24),
                        const Text(
                          'MediTrack CF Doctor',
                          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'v0.0.8',
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                        ),
                        const SizedBox(height: 32),
                        const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Color(0xFFDC143C),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }
              if (snapshot.hasData && snapshot.data != null) {
                return const DashboardScreen();
              }
              return const LoginScreen();
            },
          ),
          );
        },
      ),
    );
  }

  ThemeData _buildTheme(Brightness brightness) {
    final bool isDark = brightness == Brightness.dark;
    final base = isDark ? ThemeData.dark() : ThemeData.light();
    
    return base.copyWith(
      useMaterial3: true,
      primaryColor: const Color(0xFFDC143C), // Crimson
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFFDC143C),
        brightness: brightness,
        primary: const Color(0xFFDC143C),
        secondary: const Color(0xFFDC143C),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: const Color(0xFFDC143C),
        foregroundColor: Colors.white,
        centerTitle: true,
        elevation: 4,
        shadowColor: Colors.black26,
      ),
      scaffoldBackgroundColor: isDark ? const Color(0xFF121212) : const Color(0xFFF5F5F7), // Apple-like grey/Dark
      textTheme: GoogleFonts.nunitoTextTheme(base.textTheme), // "Nano Banana Pro" -> Nunito (Rounded/Pro)
      /* cardTheme: CardTheme(
        elevation: isDark ? 0 : 3,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        surfaceTintColor: Colors.transparent,
      ), */
    );
  }
}
