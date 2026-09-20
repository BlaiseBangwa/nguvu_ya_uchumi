import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/license_service.dart';
import 'auth/login_screen.dart';

class LicenseExpiredScreen extends StatefulWidget {
  const LicenseExpiredScreen({Key? key}) : super(key: key);

  @override
  State<LicenseExpiredScreen> createState() => _LicenseExpiredScreenState();
}

class _LicenseExpiredScreenState extends State<LicenseExpiredScreen> {
  final TextEditingController _keyController = TextEditingController();
  String? _errorMessage;
  bool _isLoading = false;

  @override
  void dispose() {
    _keyController.dispose();
    super.dispose();
  }

  Future<void> _verifyKey() async {
    final String key = _keyController.text.trim();

    if (key.isEmpty) {
      setState(() {
        _errorMessage = "Veuillez saisir une clé de renouvellement.";
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      bool success = await LicenseService.validateKey(key);

      if (!mounted) return;

      if (success) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const LoginScreen()),
              (route) => false,
        );
      } else {
        setState(() {
          _isLoading = false;
          _errorMessage = "Clé de renouvellement invalide. Contactez le développeur.";
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = "Erreur de vérification : ${e.toString()}";
        });
      }
    }
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
              const Icon(Icons.lock_clock, size: 70, color: Colors.redAccent),
              const SizedBox(height: 16),
              Text(
                "Période d'évaluation expirée",
                style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                "La période d'utilisation est arrivée à terme. Veuillez saisir votre clé de renouvellement pour continuer.",
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(fontSize: 13, color: Colors.grey[700]),
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _keyController,
                enabled: !_isLoading,
                decoration: InputDecoration(
                  labelText: "Clé de renouvellement",
                  errorText: _errorMessage,
                  prefixIcon: const Icon(Icons.key, color: Color(0xFF0F766E)),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0F766E),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: _isLoading ? null : _verifyKey,
                  child: _isLoading
                      ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                  )
                      : Text(
                    "Activer",
                    style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}