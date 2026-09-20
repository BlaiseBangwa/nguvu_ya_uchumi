import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/notification_service.dart';
import '../manage_users_screen.dart';
import '../caisse_screen.dart';
import '../reports_screen.dart';
import '../meetings_screen.dart';
import 'chat_screen.dart';
import 'suggestions_screen.dart';
import '../../pages/settings_page.dart';
import '../auth/login_screen.dart';

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({Key? key}) : super(key: key);

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  final SupabaseClient _supabase = Supabase.instance.client;
  bool _isLoading = true;

  int _totalMembers = 0;
  int _totalCollecteurs = 0;
  int _totalTresoriers = 0;
  double _totalCDF = 0.0;
  double _totalUSD = 0.0;

  int _unreadMessagesCount = 0;
  int _upcomingMeetingsCount = 0;
  StreamSubscription? _badgeSubscription;

  List<Map<String, dynamic>> _membersList = [];

  void _showAddExpenseDialog() {
    final amountController = TextEditingController();
    final descriptionController = TextEditingController();
    String selectedCurrency = 'CDF';
    String selectedCategory = 'Loyer/Bureau';

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Row(
                children: [
                  const Icon(Icons.remove_circle_outline, color: Colors.redAccent),
                  const SizedBox(width: 8),
                  Text("Enregistrer une Dépense",
                      style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 16)),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: TextFormField(
                            controller: amountController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(labelText: "Montant *"),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: selectedCurrency,
                            items: const [
                              DropdownMenuItem(value: 'CDF', child: Text("CDF")),
                              DropdownMenuItem(value: 'USD', child: Text("USD")),
                            ],
                            onChanged: (val) {
                              if (val != null) setDialogState(() => selectedCurrency = val);
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 15),
                    DropdownButtonFormField<String>(
                      value: selectedCategory,
                      decoration: const InputDecoration(labelText: "Catégorie"),
                      items: const [
                        DropdownMenuItem(value: 'Loyer/Bureau', child: Text("Loyer/Bureau")),
                        DropdownMenuItem(value: 'Transport', child: Text("Transport")),
                        DropdownMenuItem(value: 'Social/Aide', child: Text("Social/Aide")),
                        DropdownMenuItem(value: 'Fournitures', child: Text("Fournitures")),
                        DropdownMenuItem(value: 'Autre', child: Text("Autre")),
                      ],
                      onChanged: (val) {
                        if (val != null) setDialogState(() => selectedCategory = val);
                      },
                    ),
                    const SizedBox(height: 15),
                    TextFormField(
                      controller: descriptionController,
                      decoration: const InputDecoration(labelText: "Description/Motif"),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text("Annuler")),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
                  onPressed: () async {
                    if (amountController.text.isEmpty) return;
                    final amount = double.tryParse(amountController.text);
                    if (amount == null) return;

                    try {
                      await _supabase.from('transactions').insert({
                        'amount': amount,
                        'currency': selectedCurrency,
                        'type': 'EXPENSE',
                        'category': selectedCategory,
                        'description': descriptionController.text.trim(),
                        'status': 'APPROVED',
                        'created_at': DateTime.now().toIso8601String(),
                      });
                      if (mounted) {
                        Navigator.pop(context);
                        _showSnackBar("Dépense enregistrée", Colors.green);
                        _loadDashboardData();
                      }
                    } catch (e) {
                      _showSnackBar("Erreur : $e", Colors.redAccent);
                    }
                  },
                  child: const Text("Valider",
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  void initState() {
    super.initState();
    _loadDashboardData();
    _fetchNotificationBadges();
    _initBadgeListener();
  }

  @override
  void dispose() {
    _badgeSubscription?.cancel();
    super.dispose();
  }

  void _initBadgeListener() {
    _badgeSubscription = _supabase
        .from('chat_messages')
        .stream(primaryKey: ['id'])
        .listen((payload) {
      if (payload.isNotEmpty) {
        final lastMsg = payload.last;
        final currentUserId = _supabase.auth.currentUser?.id;
        if (lastMsg['user_id'] != currentUserId) {
          NotificationService.showNotification(
            id: 101,
            title: "Nouveau message",
            body: lastMsg['message'] ?? '',
          );
        }
      }
      _fetchNotificationBadges();
    });

    _supabase
        .from('meetings')
        .stream(primaryKey: ['id'])
        .listen((_) => _fetchNotificationBadges());
  }

  Future<void> _fetchNotificationBadges() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    try {
      // 1. Compter les messages non lus
      // On décompose la requête pour éviter les erreurs de type dot-shorthand
      final query = _supabase.from('chat_messages').select('id');
      final msgRes = await query.neq('user_id', user.id).eq('is_read', false);
      final List msgList = msgRes as List;

      // 2. Compter les réunions programmées
      final meetingQuery = _supabase.from('meetings').select('id');
      final meetingRes = await meetingQuery.gte('meeting_date', DateTime.now().toIso8601String());

      if (mounted) {
        setState(() {
          _unreadMessagesCount = msgList.length;
          _upcomingMeetingsCount = (meetingRes as List).length;
        });
      }
    } catch (_) {}
  }

  Future<void> _loadDashboardData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      // 1. Charger les utilisateurs et les rôles
      final membersRes = await _supabase.from('profiles').select('id, full_name, username, role');
      final membersData = List<Map<String, dynamic>>.from(membersRes);

      int countMembers = 0;
      int countCollecteurs = 0;
      int countTresoriers = 0;

      for (var user in membersData) {
        final role = (user['role'] ?? '').toString().toUpperCase().trim();
        if (role == 'COLLECTEUR') {
          countCollecteurs++;
        } else if (role == 'TRESORIER' || role == 'CAISSIER') {
          countTresoriers++;
        } else {
          countMembers++;
        }
      }

      // 2. Charger les montants depuis la table "transactions"
      double cdf = 0.0;
      double usd = 0.0;

      try {
        final transactionsRes = await _supabase
            .from('transactions')
            .select('amount, currency, type')
            .eq('status', 'APPROVED');

        final transactionsData = List<Map<String, dynamic>>.from(transactionsRes);

        for (var item in transactionsData) {
          final amount = (item['amount'] as num?)?.toDouble() ?? 0.0;
          final currency = (item['currency'] ?? 'CDF').toString().toUpperCase();
          final type = (item['type'] ?? 'INCOME').toString().toUpperCase();

          if (currency == 'USD' || currency == '\$') {
            usd += (type == 'INCOME' || type == 'ENTREE' || type == 'COTISATION') ? amount : -amount;
          } else {
            cdf += (type == 'INCOME' || type == 'ENTREE' || type == 'COTISATION') ? amount : -amount;
          }
        }
      } catch (_) {
        final transactionsRes = await _supabase.from('transactions').select('amount, currency, type');
        final transactionsData = List<Map<String, dynamic>>.from(transactionsRes);
        for (var item in transactionsData) {
          final amount = (item['amount'] as num?)?.toDouble() ?? 0.0;
          final currency = (item['currency'] ?? 'CDF').toString().toUpperCase();
          if (currency == 'USD' || currency == '\$') {
            usd += amount;
          } else {
            cdf += amount;
          }
        }
      }

      if (mounted) {
        setState(() {
          _totalMembers = countMembers;
          _totalCollecteurs = countCollecteurs;
          _totalTresoriers = countTresoriers;
          _membersList = membersData;
          _totalCDF = cdf;
          _totalUSD = usd;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        _showSnackBar("Erreur de chargement : ${e.toString()}", Colors.redAccent);
      }
    }
  }

  Future<void> _handleLogout() async {
    try {
      await _supabase.auth.signOut();
    } catch (_) {}

    if (mounted) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const LoginScreen()),
            (route) => false,
      );
    }
  }

  void _showSnackBar(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: GoogleFonts.poppins()),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  void _showAddContributionDialog() {
    String? selectedUserId;

    final amountController = TextEditingController(text: "500");
    String selectedCurrency = 'CDF';
    String selectedType = 'Journalière';
    final noteController = TextEditingController();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Row(
                children: [
                  const Icon(Icons.add_card, color: Color(0xFF0F766E)),
                  const SizedBox(width: 8),
                  Text("Nouvelle Cotisation", style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 16)),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      value: selectedUserId,
                      decoration: const InputDecoration(labelText: "Sélectionner le membre *"),
                      items: _membersList.map((m) {
                        final name = m['full_name'] ?? m['username'] ?? 'Membre';
                        return DropdownMenuItem<String>(
                          value: m['id'].toString(),
                          child: Text(name, overflow: TextOverflow.ellipsis),
                        );
                      }).toList(),
                      onChanged: (val) {
                        setDialogState(() {
                          selectedUserId = val;
                        });
                      },
                    ),
                    const SizedBox(height: 10),

                    Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: TextFormField(
                            controller: amountController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(labelText: "Montant *"),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 1,
                          child: DropdownButtonFormField<String>(
                            value: selectedCurrency,
                            decoration: const InputDecoration(labelText: "Devise"),
                            items: const [
                              DropdownMenuItem(value: 'CDF', child: Text("CDF")),
                              DropdownMenuItem(value: 'USD', child: Text("USD")),
                            ],
                            onChanged: (v) {
                              if (v != null) setDialogState(() => selectedCurrency = v);
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    DropdownButtonFormField<String>(
                      value: selectedType,
                      decoration: const InputDecoration(labelText: "Type de Cotisation"),
                      items: const [
                        DropdownMenuItem(value: 'Journalière', child: Text("Journalière (500 FC)")),
                        DropdownMenuItem(value: 'Hebdomadaire', child: Text("Hebdomadaire (2000 FC)")),
                        DropdownMenuItem(value: 'Mensuelle', child: Text("Mensuelle")),
                        DropdownMenuItem(value: 'Exceptionnelle', child: Text("Exceptionnelle")),
                        DropdownMenuItem(value: 'Secours/Social', child: Text("Secours/Social")),
                      ],
                      onChanged: (v) {
                        setDialogState(() {
                          if (v != null) selectedType = v;
                          if (v == 'Journalière') amountController.text = "500";
                          if (v == 'Hebdomadaire') amountController.text = "2000";
                        });
                      },
                    ),
                    const SizedBox(height: 10),

                    TextFormField(
                      controller: noteController,
                      decoration: const InputDecoration(labelText: "Note / Observation (Optionnel)"),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    amountController.dispose();
                    noteController.dispose();
                    Navigator.pop(context);
                  },
                  child: Text("Annuler", style: GoogleFonts.poppins(color: Colors.grey)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0F766E),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () async {
                    if (selectedUserId == null) {
                      _showSnackBar("Veuillez sélectionner un membre", Colors.orange);
                      return;
                    }

                    final amount = double.tryParse(amountController.text.trim()) ?? 0.0;
                    if (amount <= 0) {
                      _showSnackBar("Veuillez entrer un montant valide", Colors.orange);
                      return;
                    }

                    final String noteText = noteController.text.trim();
                    amountController.dispose();
                    noteController.dispose();
                    Navigator.pop(context);

                    try {
                      final currentUser = _supabase.auth.currentUser;

                      // Insertion directe dans la table "transactions"
                      await _supabase.from('transactions').insert({
                        'user_id': selectedUserId,
                        'amount': amount,
                        'currency': selectedCurrency,
                        'type': 'INCOME',
                        'category': selectedType,
                        'description': noteText,
                        'status': 'APPROVED',
                        'approved_by': currentUser?.id,
                        'approved_at': DateTime.now().toIso8601String(),
                        'created_at': DateTime.now().toIso8601String(),
                      });

                      // Notification de paiement
                      try {
                        await _supabase.from('notifications').insert({
                          'user_id': selectedUserId,
                          'title': '💰 Nouvelle Cotisation',
                          'message': 'Cotisation de $amount $selectedCurrency ($selectedType) enregistrée.',
                          'type': 'PAYMENT',
                          'created_at': DateTime.now().toIso8601String(),
                        });
                      } catch (_) {}

                      if (mounted) {
                        _showSnackBar("Cotisation enregistrée avec succès !", Colors.green);
                        _loadDashboardData();
                      }
                    } catch (e) {
                      if (mounted) {
                        _showSnackBar("Erreur lors de l'enregistrement : ${e.toString()}", Colors.redAccent);
                      }
                    }
                  },
                  child: Text("Enregistrer", style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text("Espace Administration", style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 18)),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF0F172A),
        elevation: 0.5,
        actions: [
          // Réunions avec Badge
          Stack(
            alignment: Alignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.event_available, color: Color(0xFF0F766E)),
                tooltip: "Réunions",
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MeetingsScreen(isAdmin: true))).then((_) => _fetchNotificationBadges()),
              ),
              if (_upcomingMeetingsCount > 0)
                Positioned(
                  right: 6,
                  top: 8,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                    constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                    child: Text(
                      '$_upcomingMeetingsCount',
                      style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
            ],
          ),

          // Messages avec Badge
          Stack(
            alignment: Alignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.chat_outlined, color: Color(0xFF0F766E)),
                tooltip: "Espace de Discussion",
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ChatScreen())).then((_) => _fetchNotificationBadges()),
              ),
              if (_unreadMessagesCount > 0)
                Positioned(
                  right: 6,
                  top: 8,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(color: Colors.orange, shape: BoxShape.circle),
                    constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                    child: Text(
                      '$_unreadMessagesCount',
                      style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
            ],
          ),

          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: "Actualiser",
            onPressed: () {
              _loadDashboardData();
              _fetchNotificationBadges();
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.redAccent),
            tooltip: "Déconnexion",
            onPressed: _handleLogout,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF0F766E)))
          : RefreshIndicator(
        onRefresh: () async {
          await _loadDashboardData();
          await _fetchNotificationBadges();
        },
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Aperçu général", style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
              const SizedBox(height: 10),

              Row(
                children: [
                  Expanded(
                    child: _buildStatCard(
                      title: "Membres",
                      value: "$_totalMembers",
                      icon: Icons.people,
                      color: Colors.blue,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildStatCard(
                      title: "Collecteurs",
                      value: "$_totalCollecteurs",
                      icon: Icons.assignment_ind,
                      color: Colors.orange,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _buildStatCard(
                      title: "Caissiers",
                      value: "$_totalTresoriers",
                      icon: Icons.account_balance_wallet,
                      color: Colors.purple,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildStatCard(
                      title: "Solde CDF",
                      value: "${_totalCDF.toStringAsFixed(0)} FC",
                      icon: Icons.monetization_on,
                      color: Colors.teal,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 20),
              Text("NGUVU YA UCHUMI", style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
              const SizedBox(height: 10),

              _buildAdminMenuItem(
                icon: Icons.manage_accounts,
                title: "Gestion des utilisateurs & rôles",
                subtitle: "Valider, modifier ou bloquer des membres",
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ManageUsersScreen())).then((_) => _loadDashboardData()),
              ),
              _buildAdminMenuItem(
                icon: Icons.account_balance,
                title: "Gestion de la Caisse & Cotisations",
                subtitle: "Enregistrer entrées/sorties et voir l'historique",
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CaisseScreen())).then((_) => _loadDashboardData()),
              ),
              _buildAdminMenuItem(
                icon: Icons.money_off,
                title: "Enregistrer une Dépense",
                subtitle: "Saisir une sortie de fonds (Loyer, Aide, etc.)",
                onTap: _showAddExpenseDialog,
              ),
              _buildAdminMenuItem(
                icon: Icons.lightbulb_outline,
                title: "Boîte aux Suggestions",
                subtitle: "Lire les propositions des membres",
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SuggestionsScreen(isAdmin: true))),
              ),
              _buildAdminMenuItem(
                icon: Icons.bar_chart,
                title: "Rapports & Statistiques",
                subtitle: "Exporter les bilans et relevés financiers",
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ReportsScreen())),
              ),
              _buildAdminMenuItem(
                icon: Icons.event,
                title: "Réunions & Calendrier",
                subtitle: "Organiser des rencontres et suivre les présences",
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MeetingsScreen(isAdmin: true))).then((_) => _fetchNotificationBadges()),
              ),
              _buildAdminMenuItem(
                icon: Icons.forum,
                title: "Espace de Discussion",
                subtitle: "Échanger des messages avec tous les membres",
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ChatScreen())).then((_) => _fetchNotificationBadges()),
              ),
              _buildAdminMenuItem(
                icon: Icons.settings,
                title: "Paramètres du système",
                subtitle: "Configuration générale de l'application",
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsPage())),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddContributionDialog,
        backgroundColor: const Color(0xFF0F766E),
        icon: const Icon(Icons.add, color: Colors.white),
        label: Text("Enregistrer Cotisation", style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _buildStatCard({required String title, required String value, required IconData icon, required Color color}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 8),
          Text(value, style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.bold, color: const Color(0xFF0F172A))),
          Text(title, style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade600)),
        ],
      ),
    );
  }

  Widget _buildAdminMenuItem({required IconData icon, required String title, required String subtitle, required VoidCallback onTap}) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: Colors.grey.shade200)),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: const Color(0xFF0F766E).withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
          child: Icon(icon, color: const Color(0xFF0F766E)),
        ),
        title: Text(title, style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle, style: GoogleFonts.poppins(fontSize: 11, color: Colors.grey.shade600)),
        trailing: const Icon(Icons.chevron_right, color: Colors.grey),
        onTap: onTap,
      ),
    );
  }
}