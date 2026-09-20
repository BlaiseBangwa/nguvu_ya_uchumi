import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/notification_service.dart';
import '../auth/login_screen.dart';
import 'chat_screen.dart';

class CaissierDashboard extends StatefulWidget {
  const CaissierDashboard({Key? key}) : super(key: key);

  @override
  State<CaissierDashboard> createState() => _CaissierDashboardState();
}

class _CaissierDashboardState extends State<CaissierDashboard> {
  final SupabaseClient _supabase = Supabase.instance.client;
  bool _isLoading = true;

  double _totalCDF = 0.0;
  double _totalUSD = 0.0;
  int _unreadMessagesCount = 0;

  List<Map<String, dynamic>> _membersList = [];
  List<Map<String, dynamic>> _recentTransactions = [];
  List<Map<String, dynamic>> _lateMembers = [];
  List<Map<String, dynamic>> _pendingCollectorTransactions = [];
  List<Map<String, dynamic>> _pendingAdhesions = [];
  StreamSubscription? _msgSubscription;
  StreamSubscription? _realtimeSubscription;

  @override
  void initState() {
    super.initState();
    _loadCaissierData();
    _fetchUnreadMessages();
    _initRealtimeMessages();
    _initRealtimeListener();
  }

  @override
  void dispose() {
    _msgSubscription?.cancel();
    _realtimeSubscription?.cancel();
    super.dispose();
  }

  void _initRealtimeListener() {
    // Écoute les changements sur toutes les transactions et profils
    _realtimeSubscription = _supabase
        .from('transactions')
        .stream(primaryKey: ['id'])
        .listen((_) {
      _loadCaissierData(showLoader: false);
    });
  }

  void _initRealtimeMessages() {
    _msgSubscription = _supabase
        .from('chat_messages')
        .stream(primaryKey: ['id'])
        .listen((payload) {
      if (payload.isNotEmpty) {
        final lastMsg = payload.last;
        final currentUserId = _supabase.auth.currentUser?.id;
        if (lastMsg['user_id'] != currentUserId) {
          NotificationService.showNotification(
            id: 102,
            title: "Message entrant (Caissier)",
            body: lastMsg['message'] ?? '',
          );
        }
      }
      _fetchUnreadMessages();
    });
  }

  Future<void> _fetchUnreadMessages() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    try {
      final query = _supabase.from('chat_messages').select('id');
      final msgRes = await query.neq('user_id', user.id).eq('is_read', false);

      if (mounted) {
        setState(() {
          _unreadMessagesCount = (msgRes as List).length;
        });
      }
    } catch (_) {}
  }

  Future<void> _loadCaissierData({bool showLoader = true}) async {
    if (!mounted) return;
    if (showLoader) setState(() => _isLoading = true);

    try {
      // 1. Récupération de la liste des membres (approuvés et non approuvés)
      final profilesRes = await _supabase
          .from('profiles')
          .select('id, full_name, username, phone, role, is_approved')
          .order('full_name', ascending: true);

      final profilesData = List<Map<String, dynamic>>.from(profilesRes);
      final membersData = profilesData.where((p) => p['is_approved'] == true).toList();
      final pendingAdhesionsData = profilesData.where((p) => p['is_approved'] == false).toList();

      // 2. Récupération des transactions
      final transRes = await _supabase
          .from('transactions')
          .select('id, amount, currency, category, type, description, created_at, user_id, status, profiles:user_id(full_name, username)')
          .order('created_at', ascending: false);

      final transData = List<Map<String, dynamic>>.from(transRes);

      // 3. Calcul du solde & Filtrage des transactions terrain et cotisations du jour
      double cdf = 0.0;
      double usd = 0.0;
      final Set<String> paidTodayUserIds = {};
      final String todayStr = DateTime.now().toIso8601String().substring(0, 10);
      final List<Map<String, dynamic>> collectorTransactions = [];

      for (var item in transData) {
        final amount = (item['amount'] as num?)?.toDouble() ?? 0.0;
        final currency = (item['currency'] ?? 'CDF').toString().toUpperCase();
        final type = (item['type'] ?? 'INCOME').toString().toUpperCase();
        final createdAt = (item['created_at'] ?? '').toString();
        final userId = item['user_id']?.toString();
        final status = item['status'] ?? 'APPROVED';

        // Transactions à valider par le caissier
        if (status == 'PENDING_CAISSIER') {
          collectorTransactions.add(item);
        }

        if (status == 'APPROVED') {
          if (currency == 'USD' || currency == '\$') {
            usd += (type == 'INCOME' || type == 'ENTREE' || type == 'COTISATION') ? amount : -amount;
          } else {
            cdf += (type == 'INCOME' || type == 'ENTREE' || type == 'COTISATION') ? amount : -amount;
          }
        }

        if (createdAt.startsWith(todayStr) && userId != null && status == 'APPROVED') {
          paidTodayUserIds.add(userId);
        }
      }

      // 4. Filtrer les membres en retard pour la journée
      final List<Map<String, dynamic>> pendingLate = [];
      for (var member in membersData) {
        final memberId = (member['id'] ?? '').toString();
        if (memberId.isNotEmpty && !paidTodayUserIds.contains(memberId)) {
          pendingLate.add(member);
        }
      }

      if (mounted) {
        setState(() {
          _membersList = membersData;
          _recentTransactions = transData.where((t) => t['status'] == 'APPROVED').take(30).toList();
          _pendingCollectorTransactions = collectorTransactions;
          _pendingAdhesions = pendingAdhesionsData;
          _lateMembers = pendingLate;
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

  Future<void> _approveTransaction(String id) async {
    try {
      final user = _supabase.auth.currentUser;
      await _supabase.from('transactions').update({
        'status': 'APPROVED',
        'approved_by': user?.id,
        'approved_at': DateTime.now().toIso8601String(),
      }).eq('id', id);
      _showSnackBar("Transaction validée avec succès !", Colors.green);
      _loadCaissierData(showLoader: false);
    } catch (e) {
      _showSnackBar("Erreur de validation : $e", Colors.redAccent);
    }
  }

  Future<void> _approveMember(String id) async {
    try {
      await _supabase.from('profiles').update({
        'is_approved': true,
      }).eq('id', id);
      _showSnackBar("Membre approuvé !", Colors.green);
      _loadCaissierData(showLoader: false);
    } catch (e) {
      _showSnackBar("Erreur : $e", Colors.redAccent);
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

  void _showAddContributionDialog({String? preselectedUserId}) {
    String? selectedUserId = preselectedUserId;
    final amountController = TextEditingController(text: "500");
    final searchController = TextEditingController();
    String selectedCurrency = 'CDF';
    String selectedType = 'Journalière (500 FC)';
    final noteController = TextEditingController();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final filteredMembers = _membersList.where((m) {
              final name = (m['full_name'] ?? m['username'] ?? '').toString().toLowerCase();
              return name.contains(searchController.text.toLowerCase());
            }).toList();

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
                    TextFormField(
                      controller: searchController,
                      decoration: const InputDecoration(
                        labelText: "Rechercher un membre",
                        prefixIcon: Icon(Icons.search, size: 20),
                        isDense: true,
                      ),
                      onChanged: (_) => setDialogState(() {}),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      value: filteredMembers.any((m) => m['id'].toString() == selectedUserId) ? selectedUserId : null,
                      decoration: const InputDecoration(labelText: "Sélectionner le membre *"),
                      items: filteredMembers.map((m) {
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
                        DropdownMenuItem(value: 'Journalière (500 FC)', child: Text("Journalière (500 FC)")),
                        DropdownMenuItem(value: 'Hebdomadaire (2000 FC)', child: Text("Hebdomadaire (2000 FC)")),
                        DropdownMenuItem(value: 'Mensuelle', child: Text("Mensuelle")),
                        DropdownMenuItem(value: 'Exceptionnelle', child: Text("Exceptionnelle")),
                        DropdownMenuItem(value: 'Secours/Social', child: Text("Secours/Social")),
                      ],
                      onChanged: (v) {
                        setDialogState(() {
                          if (v != null) {
                            selectedType = v;
                            if (v.contains('500')) amountController.text = "500";
                            if (v.contains('2000')) amountController.text = "2000";
                          }
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
                    searchController.dispose();
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
                    searchController.dispose();
                    noteController.dispose();
                    Navigator.pop(context);

                    try {
                      final currentUser = _supabase.auth.currentUser;

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

                      try {
                        await _supabase.from('notifications').insert({
                          'user_id': selectedUserId,
                          'title': '💰 Cotisation Enregistrée',
                          'message': 'Votre cotisation de $amount $selectedCurrency ($selectedType) a été enregistrée par le caissier.',
                          'type': 'PAYMENT',
                          'created_at': DateTime.now().toIso8601String(),
                        });
                      } catch (_) {}

                      if (mounted) {
                        _showSnackBar("Cotisation enregistrée avec succès !", const Color(0xFF0F766E));
                        _loadCaissierData();
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
        title: Text("Espace Caissier / Caisse", style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 18)),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF0F172A),
        elevation: 0.5,
        actions: [
          Stack(
            alignment: Alignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.chat_outlined, color: Color(0xFF0F766E)),
                tooltip: "Discussion",
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ChatScreen())).then((_) => _fetchUnreadMessages()),
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
              _loadCaissierData();
              _fetchUnreadMessages();
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
          await _loadCaissierData();
          await _fetchUnreadMessages();
        },
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("Solde CDF", style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey)),
                          Text("${_totalCDF.toStringAsFixed(0)} FC", style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.bold, color: const Color(0xFF0F766E))),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("Solde USD", style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey)),
                          Text("${_totalUSD.toStringAsFixed(2)} \$", style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blueAccent)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 22),
                  const SizedBox(width: 8),
                  Text(
                    "Alertes de Retard du Jour (${_lateMembers.length})",
                    style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 15, color: const Color(0xFF0F172A)),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                "Membres qui n'ont pas encore cotisé aujourd'hui :",
                style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 10),

              _lateMembers.isEmpty
                  ? Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.green.shade200),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle_outline, color: Colors.green, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        "Tous les membres ont effectué leur cotisation aujourd'hui !",
                        style: GoogleFonts.poppins(fontSize: 12, color: Colors.green.shade800, fontWeight: FontWeight.w500),
                      ),
                    ),
                  ],
                ),
              )
                  : Container(
                constraints: const BoxConstraints(maxHeight: 220),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _lateMembers.length,
                  itemBuilder: (context, index) {
                    final member = _lateMembers[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      color: Colors.amber.shade50,
                      elevation: 0,
                      child: ListTile(
                        dense: true,
                        leading: CircleAvatar(
                          radius: 16,
                          backgroundColor: Colors.amber.shade200,
                          child: const Icon(Icons.access_time_filled, color: Colors.amber, size: 16),
                        ),
                        title: Text(
                          member['full_name'] ?? member['username'] ?? 'Membre',
                          style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        subtitle: Text(
                          "Tél: ${member['phone'] ?? '-'}",
                          style: GoogleFonts.poppins(fontSize: 11, color: Colors.grey.shade700),
                        ),
                        trailing: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orange.shade800,
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                            minimumSize: const Size(60, 30),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          onPressed: () {
                            _showAddContributionDialog(preselectedUserId: member['id'].toString());
                          },
                          child: Text(
                            "Cotiser",
                            style: GoogleFonts.poppins(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),

              const SizedBox(height: 25),

              // SECTION VALIDATION TERRAIN
              if (_pendingCollectorTransactions.isNotEmpty) ...[
                Row(
                  children: [
                    const Icon(Icons.terrain, color: Colors.indigo, size: 22),
                    const SizedBox(width: 8),
                    Text(
                      "Validations Terrain (${_pendingCollectorTransactions.length})",
                      style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 15, color: const Color(0xFF0F172A)),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ..._pendingCollectorTransactions.map((tx) {
                  final profile = tx['profiles'] as Map<String, dynamic>?;
                  final memberName = profile?['full_name'] ?? profile?['username'] ?? 'Membre';
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    color: Colors.indigo.shade50,
                    child: ListTile(
                      title: Text(memberName, style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text("${tx['amount']} ${tx['currency']} • ${tx['category']}"),
                      trailing: ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo, foregroundColor: Colors.white),
                        onPressed: () => _approveTransaction(tx['id']),
                        child: const Text("Valider", style: TextStyle(fontSize: 11)),
                      ),
                    ),
                  );
                }).toList(),
                const SizedBox(height: 20),
              ],

              // SECTION VALIDATION ADHÉSIONS
              if (_pendingAdhesions.isNotEmpty) ...[
                Row(
                  children: [
                    const Icon(Icons.person_add_alt_1, color: Colors.blue, size: 22),
                    const SizedBox(width: 8),
                    Text(
                      "Nouvelles Adhésions (${_pendingAdhesions.length})",
                      style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 15, color: const Color(0xFF0F172A)),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ..._pendingAdhesions.map((p) {
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    color: Colors.blue.shade50,
                    child: ListTile(
                      title: Text(p['full_name'] ?? p['username'], style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text("Pseudo: ${p['username']} • Rôle: ${p['role']}"),
                      trailing: ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white),
                        onPressed: () => _approveMember(p['id']),
                        child: const Text("Approuver", style: TextStyle(fontSize: 11)),
                      ),
                    ),
                  );
                }).toList(),
                const SizedBox(height: 20),
              ],

              const SizedBox(height: 20),

              Text("Dernières cotisations", style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
              const SizedBox(height: 10),

              _recentTransactions.isEmpty
                  ? Center(child: Text("Aucune cotisation récente", style: GoogleFonts.poppins(color: Colors.grey)))
                  : ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _recentTransactions.length,
                itemBuilder: (context, index) {
                  final item = _recentTransactions[index];
                  final amount = item['amount'] ?? 0;
                  final currency = item['currency'] ?? 'CDF';
                  final category = item['category'] ?? 'Cotisation';
                  final profile = item['profiles'] as Map<String, dynamic>?;
                  final memberName = profile?['full_name'] ?? profile?['username'] ?? 'Membre';

                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    elevation: 0,
                    child: ListTile(
                      leading: const CircleAvatar(
                        backgroundColor: Color(0x1A0F766E),
                        child: Icon(Icons.arrow_downward, color: Color(0xFF0F766E), size: 20),
                      ),
                      title: Text(memberName, style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 13)),
                      subtitle: Text(
                        "$category • ${item['created_at'] != null ? item['created_at'].toString().split('T')[0] : ''}",
                        style: GoogleFonts.poppins(fontSize: 11),
                      ),
                      trailing: Text(
                        "+$amount $currency",
                        style: GoogleFonts.poppins(fontWeight: FontWeight.bold, color: const Color(0xFF0F766E), fontSize: 14),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddContributionDialog(),
        backgroundColor: const Color(0xFF0F766E),
        icon: const Icon(Icons.add_card, color: Colors.white),
        label: Text("Enregistrer Cotisation", style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
    );
  }
}