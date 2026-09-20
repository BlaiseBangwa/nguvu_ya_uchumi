import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/notification_service.dart';

import '../auth/login_screen.dart';
import 'chat_screen.dart';
import '../meetings_screen.dart';

class CollecteurDashboard extends StatefulWidget {
  const CollecteurDashboard({super.key});

  @override
  State<CollecteurDashboard> createState() => _CollecteurDashboardState();
}

class _CollecteurDashboardState extends State<CollecteurDashboard> {
  final SupabaseClient _supabase = Supabase.instance.client;
  bool _isLoading = true;

  double _totalCDF = 0.0;
  double _totalUSD = 0.0;

  List<Map<String, dynamic>> _membersList = [];
  List<Map<String, dynamic>> _myCollectionsList = [];
  int _unreadMessagesCount = 0;
  StreamSubscription? _msgSubscription;

  @override
  void initState() {
    super.initState();
    _loadCollectorData();
    _fetchUnreadMessages();
    _initRealtimeMessages();
  }

  @override
  void dispose() {
    _msgSubscription?.cancel();
    super.dispose();
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
            id: 103,
            title: "Nouveau message (Collecteur)",
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

  Future<void> _loadCollectorData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;

      // 1. Récupération des membres pour la collecte sur terrain
      final membersRes = await _supabase
          .from('profiles')
          .select('id, full_name, username')
          .order('full_name', ascending: true);

      // 2. Récupération des transactions globales (pour le rapport de caisse)
      final transRes = await _supabase
          .from('transactions')
          .select('id, amount, currency, status, user_id, collected_by, created_at, category')
          .order('created_at', ascending: false);

      final transData = List<Map<String, dynamic>>.from(transRes);

      double cdf = 0.0;
      double usd = 0.0;

      for (var item in transData) {
        final double amount = (item['amount'] as num?)?.toDouble() ?? 0.0;
        final String currency = (item['currency'] ?? 'CDF').toString().toUpperCase();
        final String status = item['status'] ?? '';

        if (status == 'APPROVED') {
          if (currency == 'USD' || currency == '\$') {
            usd += amount;
          } else {
            cdf += amount;
          }
        }
      }

      // 3. Mes collectes récentes sur terrain
      final myCollections = transData
          .where((t) => t['collected_by'].toString() == user.id)
          .take(15)
          .toList();

      if (mounted) {
        setState(() {
          _membersList = List<Map<String, dynamic>>.from(membersRes);
          _myCollectionsList = myCollections;
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

  /// Boîte de dialogue pour effectuer une collecte chez un membre
  void _showCollectMoneyDialog() {
    String? selectedUserId;
    final amountController = TextEditingController(text: "500");
    final searchController = TextEditingController();
    String selectedCurrency = 'CDF';
    String selectedType = 'Journalière (500 FC)';

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
                  const Icon(Icons.pin_drop, color: Color(0xFF0F766E)),
                  const SizedBox(width: 8),
                  Text("Collecte sur Terrain", style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 16)),
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
                      onChanged: (val) => setDialogState(() => selectedUserId = val),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: TextFormField(
                            controller: amountController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(labelText: "Montant perçu *"),
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
                      decoration: const InputDecoration(labelText: "Type de cotisations"),
                      items: const [
                        DropdownMenuItem(value: 'Journalière (500 FC)', child: Text("Journalière (500 FC)")),
                        DropdownMenuItem(value: 'Hebdomadaire (2000 FC)', child: Text("Hebdomadaire (2000 FC)")),
                        DropdownMenuItem(value: 'Mensuelle', child: Text("Mensuelle")),
                        DropdownMenuItem(value: 'Exceptionnelle', child: Text("Exceptionnelle")),
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
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
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
                      _showSnackBar("Veuillez saisir un montant valide", Colors.orange);
                      return;
                    }

                    Navigator.pop(context);

                    try {
                      final collectorUser = _supabase.auth.currentUser;

                      // Soumission avec statut PENDING_CAISSIER (attente de dépôt au caissier)
                      await _supabase.from('transactions').insert({
                        'user_id': selectedUserId,
                        'collected_by': collectorUser?.id,
                        'amount': amount,
                        'currency': selectedCurrency,
                        'type': 'INCOME',
                        'category': selectedType,
                        'description': 'Collecte sur terrain (Attente de versement caissier)',
                        'status': 'PENDING_CAISSIER',
                        'created_at': DateTime.now().toIso8601String(),
                      });

                      if (mounted) {
                        _showSnackBar("Paiement collecté ! En attente de validation du caissier.", const Color(0xFF0F766E));
                        _loadCollectorData();
                      }
                    } catch (e) {
                      if (mounted) {
                        _showSnackBar("Erreur lors de la collecte : ${e.toString()}", Colors.redAccent);
                      }
                    }
                  },
                  child: Text("Valider la collecte", style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.bold)),
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
        title: Text("Espace Collecteur", style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 18)),
        backgroundColor: const Color(0xFF0F766E),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          Stack(
            alignment: Alignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.chat_outlined, color: Colors.white),
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
            icon: const Icon(Icons.event),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MeetingsScreen(isAdmin: false))),
          ),
          IconButton(
            icon: const Icon(Icons.chat),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ChatScreen())),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadCollectorData,
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await _supabase.auth.signOut();
              if (mounted) {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                      (route) => false,
                );
              }
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF0F766E)))
          : RefreshIndicator(
        onRefresh: _loadCollectorData,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Carte Montant Global du Comité
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F766E),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Solde Global Validé du Comité", style: GoogleFonts.poppins(color: Colors.white70, fontSize: 13)),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text("USD", style: GoogleFonts.poppins(color: Colors.white60, fontSize: 11)),
                              Text("${_totalUSD.toStringAsFixed(2)} \$", style: GoogleFonts.poppins(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                        Container(height: 35, width: 1, color: Colors.white24),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(left: 16.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text("CDF / FC", style: GoogleFonts.poppins(color: Colors.white60, fontSize: 11)),
                                Text("${_totalCDF.toStringAsFixed(0)} FC", style: GoogleFonts.poppins(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Historique de mes collectes sur terrain
              Text("Mes récentes collectes sur terrain", style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.bold, color: const Color(0xFF334155))),
              const SizedBox(height: 10),

              _myCollectionsList.isEmpty
                  ? Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                child: Center(child: Text("Aucune collecte effectuée récemment.", style: GoogleFonts.poppins(color: Colors.grey))),
              )
                  : ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _myCollectionsList.length,
                itemBuilder: (context, index) {
                  final item = _myCollectionsList[index];
                  final amount = item['amount'] ?? 0;
                  final currency = item['currency'] ?? 'CDF';
                  final status = item['status'] ?? 'PENDING';
                  final isApproved = status == 'APPROVED';

                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    elevation: 0,
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: isApproved ? Colors.green.shade100 : Colors.amber.shade100,
                        child: Icon(
                          isApproved ? Icons.check_circle : Icons.hourglass_top,
                          color: isApproved ? Colors.green : Colors.amber.shade900,
                          size: 20,
                        ),
                      ),
                      title: Text("${item['category'] ?? 'Cotisation'}", style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 13)),
                      subtitle: Text(
                        item['created_at'] != null ? DateFormat('dd/MM/yyyy HH:mm').format(DateTime.parse(item['created_at']).toLocal()) : '',
                        style: GoogleFonts.poppins(fontSize: 11),
                      ),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text("+$amount $currency", style: GoogleFonts.poppins(fontWeight: FontWeight.bold, color: const Color(0xFF0F766E), fontSize: 13)),
                          Text(
                            isApproved ? 'Déposé/Validé' : 'En attente Caissier',
                            style: GoogleFonts.poppins(fontSize: 10, color: isApproved ? Colors.green : Colors.amber.shade900),
                          ),
                        ],
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
        onPressed: _showCollectMoneyDialog,
        backgroundColor: const Color(0xFF0F766E),
        icon: const Icon(Icons.add_location_alt, color: Colors.white),
        label: Text("Nouveau Recouvrement", style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
    );
  }
}