import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dashboard_screen.dart';
import '../services/auth_service.dart';
import '../utils/error_utils.dart';
import 'package:firebase_auth/firebase_auth.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final AuthService _authService = AuthService();
  bool _isLoading = false;
  bool _isLogin = true;

  void _submit() async {
    setState(() => _isLoading = true);
    try {
      if (_isLogin) {
        await _authService.signIn(
          _emailController.text.trim(), 
          _passwordController.text.trim()
        );
      } else {
        await _authService.signUp(
          _emailController.text.trim(), 
          _passwordController.text.trim()
        );
      }
      
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => DashboardScreen()),
        );
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(ErrorUtils.getFriendlyMessage(e)),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(ErrorUtils.getFriendlyMessage(e)),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isDark 
              ? [const Color(0xFF141414), const Color(0xFF000000)] 
              : [const Color(0xFFF5F5F7), const Color(0xFFE0E0E0)],
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Logo / Title area
                Container(
                  height: 64,
                  width: 64,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    image: const DecorationImage(
                      image: AssetImage('assets/logo.png'),
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  "MediTrack CF Doctor",
                  style: GoogleFonts.nunito(
                    fontSize: 32,
                    fontWeight: FontWeight.w900,
                    color: const Color(0xFFDC143C),
                    letterSpacing: 1.5,
                    shadows: [
                      Shadow(
                        color: const Color(0xFFDC143C).withOpacity(0.5),
                        blurRadius: 20,
                      )
                    ]
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  "v0.0.8",
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade500,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  "Doctor Portal",
                  style: TextStyle(
                    fontSize: 16,
                    color: isDark ? Colors.white54 : Colors.grey,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 48),

                // Glass/Card Container
                Container(
                  width: 400,
                  padding: const EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E1E1E).withOpacity(0.8) : Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: isDark ? Colors.white10 : Colors.transparent,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFDC143C).withOpacity(0.05),
                        blurRadius: 60,
                        spreadRadius: 0,
                      ),
                      BoxShadow(
                        color: Colors.black.withOpacity(0.2),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      )
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        _isLogin ? "Welcome Back" : "Create Account",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 24, 
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : Colors.black87
                        ),
                      ),
                      const SizedBox(height: 32),
                      
                      // Email Field
                      TextField(
                        controller: _emailController,
                        style: TextStyle(color: isDark ? Colors.white : Colors.black),
                        decoration: InputDecoration(
                          labelText: "Email ID",
                          prefixIcon: Icon(Icons.email_outlined, color: const Color(0xFFDC143C).withOpacity(0.8)),
                          filled: true,
                          fillColor: isDark ? Colors.black26 : Colors.grey.shade100,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Color(0xFFDC143C)),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      
                      // Password Field
                      TextField(
                        controller: _passwordController,
                        obscureText: true,
                        style: TextStyle(color: isDark ? Colors.white : Colors.black),
                        decoration: InputDecoration(
                          labelText: "Password",
                          prefixIcon: Icon(Icons.lock_outline, color: const Color(0xFFDC143C).withOpacity(0.8)),
                          filled: true,
                          fillColor: isDark ? Colors.black26 : Colors.grey.shade100,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Color(0xFFDC143C)),
                          ),
                        ),
                      ),
                      const SizedBox(height: 32),

                      // Login Button
                      SizedBox(
                        height: 50,
                        child: ElevatedButton(

                          onPressed: _isLoading ? null : _submit,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFDC143C),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 8,
                            shadowColor: const Color(0xFFDC143C).withOpacity(0.5),
                          ),
                          child: _isLoading 
                            ? SizedBox(
                                width: 20, 
                                height: 20, 
                                child: ShaderMask(
                                  shaderCallback: (bounds) {
                                    return const SweepGradient(
                                      colors: [Colors.white, Colors.white12],
                                      stops: [0.5, 1.0],
                                      transform: GradientRotation(0),
                                    ).createShader(bounds);
                                  },
                                  child: const CircularProgressIndicator(
                                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                    strokeWidth: 2,
                                  ),
                                ),
                              )
                            : Text(_isLogin ? "LOGIN" : "REGISTER", style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1)),
                        ),
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 16),
                TextButton(
                  onPressed: () => setState(() => _isLogin = !_isLogin),
                  child: Text(
                    _isLogin 
                      ? "Don't have an account? Register" 
                      : "Already have an account? Login",
                    style: const TextStyle(color: Color(0xFFDC143C)),
                  ),
                ),
                
                const SizedBox(height: 32),
                Text(
                  "Strictly for authorized medical personnel only.",
                  style: TextStyle(color: isDark ? Colors.white24 : Colors.grey.shade400, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
