import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/database_helper.dart';
import '../dashboard/admin_dashboard.dart';
import '../dashboard/caissier_dashboard.dart';
import '../dashboard/collecteur_dashboard.dart';
import '../dashboard/membre_dashboard.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final SupabaseClient _supabase = Supabase.instance.client;
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _obscureText = true;
  bool _isLoading = false;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    final username = _usernameController.text.trim().toLowerCase();
    final password = _passwordController.text.trim();

    if (username.isEmpty || password.isEmpty) {
      _showErrorSnackBar("Veuillez remplir tous les champs.");
      return;
    }

    setState(() => _isLoading = true);

    try {
      final connectivityResult = await Connectivity().checkConnectivity();
      final bool isOffline = connectivityResult.contains(ConnectivityResult.none) || connectivityResult.isEmpty;

      if (isOffline) {
        await _loginOffline(username, password);
      } else {
        await _loginOnline(username, password);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        _showErrorSnackBar("Erreur de connexion : ${e.toString()}");
      }
    }
  }

  Future<void> _loginOnline(String username, String password) async {
    try {
      // 1. Authentification Supabase Auth
      final internalEmail = '$username@nguvu.app';
      final AuthResponse res = await _supabase.auth.signInWithPassword(
        email: internalEmail,
        password: password,
      );

      if (!mounted) return;

      if (res.user == null) {
        setState(() => _isLoading = false);
        _showErrorSnackBar("Nom d'utilisateur ou mot de passe incorrect.");
        return;
      }

      // 2. Récupération sécurisée du profil avec token d'authentification
      final profileRes = await _supabase
          .from('profiles')
          .select('id, role, is_approved, username')
          .eq('id', res.user?.id ?? '')
          .maybeSingle();

      if (profileRes == null) {
        await _supabase.auth.signOut();
        if (mounted) {
          setState(() => _isLoading = false);
          _showErrorSnackBar("Profil utilisateur introuvable en base de données.");
        }
        return;
      }

      // 3. Vérification de l'approbation du compte
      final bool isApproved = profileRes['is_approved'] ?? false;
      if (!isApproved) {
        await _supabase.auth.signOut();
        if (mounted) {
          setState(() => _isLoading = false);
          _showErrorSnackBar("Compte en attente d'approbation par l'administrateur.");
        }
        return;
      }

      setState(() => _isLoading = false);
      _redirectToDashboard(profileRes['role'] ?? 'MEMBRE');
    } on AuthException catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        _showErrorSnackBar("Identifiants incorrects : ${e.message}");
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        _showErrorSnackBar("Erreur lors de la connexion : ${e.toString()}");
      }
    }
  }

  Future<void> _loginOffline(String username, String password) async {
    final db = await DatabaseHelper.instance.database;
    final List<Map<String, dynamic>> res = await db.query(
      'profiles',
      where: 'LOWER(username) = ? AND password_hash = ?',
      whereArgs: [username, password],
    );

    if (!mounted) return;

    if (res.isEmpty) {
      setState(() => _isLoading = false);
      _showErrorSnackBar("Identifiants hors-ligne incorrects.");
      return;
    }

    final user = res.first;
    final bool isApproved = (user['is_approved'] ?? 0) == 1;

    if (!isApproved) {
      setState(() => _isLoading = false);
      _showErrorSnackBar("Compte non approuvé.");
      return;
    }

    setState(() => _isLoading = false);
    _redirectToDashboard(user['role'] ?? 'MEMBRE');
  }

  void _redirectToDashboard(String role) {
    final normalizedRole = role.toString().toUpperCase().trim();
    Widget targetDashboard;

    switch (normalizedRole) {
      case 'ADMINISTRATEUR':
      case 'ADMIN':
        targetDashboard = AdminDashboard();
        break;

    // Trésorier et Caissier représentent le même agent financier
      case 'TRESORIER':
      case 'CAISSIER':
        targetDashboard = CaissierDashboard();
        break;

    // Agent de collecte sur le terrain
      case 'COLLECTEUR':
        targetDashboard = CollecteurDashboard();
        break;

      case 'MEMBRE':
      default:
        targetDashboard = MembreDashboard();
        break;
    }

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => targetDashboard),
    );
  }

  void _showErrorSnackBar(String message, {Color color = Colors.redAccent}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: GoogleFonts.poppins()),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F766E).withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.account_balance_wallet_outlined,
                  size: 50,
                  color: Color(0xFF0F766E),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                "NGUVU YA UCHUMI",
                style: GoogleFonts.poppins(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF0F172A),
                ),
              ),
              Text(
                "Gestion de Depenses & Cotisations",
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(height: 32),
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 15,
                      offset: const Offset(0, 5),
                    )
                  ],
                ),
                child: Column(
                  children: [
                    TextField(
                      controller: _usernameController,
                      decoration: InputDecoration(
                        labelText: "Nom d'utilisateur / Pseudo",
                        prefixIcon: const Icon(Icons.person_outline, size: 20),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _passwordController,
                      obscureText: _obscureText,
                      decoration: InputDecoration(
                        labelText: "Mot de passe",
                        prefixIcon: const Icon(Icons.lock_outline, size: 20),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscureText
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                            size: 20,
                          ),
                          onPressed: () =>
                              setState(() => _obscureText = !_obscureText),
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0F766E),
                          disabledBackgroundColor: const Color(0xFF0F766E).withOpacity(0.6),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 0,
                        ),
                        onPressed: _isLoading ? null : _handleLogin,
                        child: _isLoading
                            ? const SizedBox(
                          height: 24,
                          width: 24,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2.5,
                          ),
                        )
                            : Text(
                          "Se Connecter",
                          style: GoogleFonts.poppins(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ),
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