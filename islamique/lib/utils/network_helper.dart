import 'dart:io';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';

class NetworkHelper {
  static void handleError(BuildContext context, dynamic error) {
    String message = "Une erreur est survenue.";

    if (error is SocketException || error.toString().contains('SocketException') || error.toString().contains('NetworkImage')) {
      message = "Pas de connexion Internet. Veuillez vérifier votre réseau.";
    } else if (error is PostgrestException) {
      message = "Erreur Supabase : ${error.message}";
    } else if (error is AuthException) {
      message = "Erreur d'authentification : ${error.message}";
    } else {
      message = error.toString();
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: GoogleFonts.poppins(color: Colors.white),
        ),
        backgroundColor: Colors.redAccent,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
}