import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Import de votre configuration Supabase existante
import 'config/supabase_config.dart';

// Imports des écrans d'authentification
import 'screens/auth/login_screen.dart';

// Imports des dashboards par rôle
import 'screens/dashboard/admin_dashboard.dart';
import 'screens/dashboard/caissier_dashboard.dart';
import 'screens/dashboard/collecteur_dashboard.dart';
import 'screens/dashboard/membre_dashboard.dart';
import 'screens/dashboard/chat_screen.dart';
import 'screens/dashboard/suggestions_screen.dart';

// Imports des écrans secondaires
import 'screens/manage_users_screen.dart';
import 'screens/meetings_screen.dart';
import 'screens/caisse_screen.dart';
import 'screens/reports_screen.dart';
import 'screens/license_expired_screen.dart';
import 'services/notification_service.dart';

void main() async {
  // Nécessaire avant d'exécuter du code asynchrone au démarrage
  WidgetsFlutterBinding.ensureInitialized();

  // Initialisation des notifications locales
  await NotificationService.init();

  // Initialisation du client Supabase
  await Supabase.initialize(
    url: SupabaseConfig.url,
    anonKey: SupabaseConfig.anonKey,
  );

  runApp(const TontineApp());
}

class TontineApp extends StatelessWidget {
  const TontineApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Comité Islamique',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0F766E),
          primary: const Color(0xFF0F766E),
        ),
        textTheme: GoogleFonts.poppinsTextTheme(
          Theme.of(context).textTheme,
        ),
      ),
      home: const AuthWrapper(),
      routes: {
        '/login': (context) => LoginScreen(),
        '/admin-dashboard': (context) => AdminDashboard(),
        '/caissier-dashboard': (context) => CaissierDashboard(),
        '/collecteur-dashboard': (context) => CollecteurDashboard(),
        '/membre-dashboard': (context) => MembreDashboard(),
        '/manage-users': (context) => ManageUsersScreen(),
        '/meetings': (context) => MeetingsScreen(),
        '/chat': (context) => ChatScreen(),
        '/suggestions': (context) => SuggestionsScreen(isAdmin: false),
        '/admin-suggestions': (context) => SuggestionsScreen(isAdmin: true),
        '/caisse': (context) => CaisseScreen(),
        '/reports': (context) => ReportsScreen(),
        '/license-expired': (context) => LicenseExpiredScreen(),
      },
    );
  }
}

/// Composant de routage initial qui contrôle la session et le rôle de l'utilisateur
class AuthWrapper extends StatefulWidget {
  const AuthWrapper({Key? key}) : super(key: key);

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  final SupabaseClient _supabase = Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _checkSessionAndRedirect();
  }

  Future<void> _checkSessionAndRedirect() async {
    final session = _supabase.auth.currentSession;
    final user = _supabase.auth.currentUser;

    // S'il n'y a pas de session active, diriger vers la connexion
    if (session == null || user == null) {
      if (mounted) {
        Navigator.pushReplacementNamed(context, '/login');
      }
      return;
    }

    try {
      // Récupération du rôle dans le profil utilisateur Supabase
      final res = await _supabase
          .from('profiles')
          .select('role')
          .eq('id', user.id)
          .maybeSingle();

      String role = 'MEMBRE';
      if (res != null && res['role'] != null) {
        role = res['role'].toString().toUpperCase().trim();
      }

      if (!mounted) return;

      // Routage strict vers l'espace correspondant au rôle
      switch (role) {
        case 'ADMINISTRATEUR':
        case 'ADMIN':
          Navigator.pushReplacementNamed(context, '/admin-dashboard');
          break;
        case 'TRESORIER':
        case 'CAISSIER':
          Navigator.pushReplacementNamed(context, '/caissier-dashboard');
          break;
        case 'COLLECTEUR':
          Navigator.pushReplacementNamed(context, '/collecteur-dashboard');
          break;
        case 'MEMBRE':
        default:
          Navigator.pushReplacementNamed(context, '/membre-dashboard');
          break;
      }
    } catch (e) {
      if (mounted) {
        Navigator.pushReplacementNamed(context, '/login');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: CircularProgressIndicator(color: Color(0xFF0F766E)),
      ),
    );
  }
}