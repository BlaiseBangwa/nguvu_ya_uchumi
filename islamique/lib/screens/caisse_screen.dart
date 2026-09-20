import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class CaisseScreen extends StatefulWidget {
  const CaisseScreen({Key? key}) : super(key: key);

  @override
  State<CaisseScreen> createState() => _CaisseScreenState();
}

class _CaisseScreenState extends State<CaisseScreen> {
  final SupabaseClient _supabase = Supabase.instance.client;
  bool _isLoading = true;

  double _totalCDF = 0.0;
  double _totalUSD = 0.0;
  List<Map<String, dynamic>> _membersList = [];
  List<Map<String, dynamic>> _recentTransactions = [];
  List<Map<String, dynamic>> _lateMembersList = [];
  StreamSubscription? _realtimeSubscription;

  bool _isAdmin = false;

  static const double _dailyTargetCDF = 500.0; // Seuil journalier de cotisation (500 FC/jour)

  @override
  void initState() {
    super.initState();
    _checkRole();
    _loadCaisseData();
    _initRealtimeListener();
  }

  Future<void> _checkRole() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;
    final res = await _supabase.from('profiles').select('role').eq('id', user.id).maybeSingle();
    if (mounted && res != null) {
      setState(() {
        _isAdmin = res['role'].toString().toUpperCase() == 'ADMIN';
      });
    }
  }

  @override
  void dispose() {
    _realtimeSubscription?.cancel();
    super.dispose();
  }

  void _initRealtimeListener() {
    // Écoute les changements sur toutes les transactions
    _realtimeSubscription = _supabase
        .from('transactions')
        .stream(primaryKey: ['id'])
        .listen((_) {
      _loadCaisseData(showLoader: false);
    });
  }

  /// Chargement global des données de caisse, membres et retards
  Future<void> _loadCaisseData({bool showLoader = true}) async {
    if (!mounted) return;
    if (showLoader) setState(() => _isLoading = true);

    try {
      // 1. Récupération des membres
      final membersRes = await _supabase
          .from('profiles')
          .select('id, full_name, username, created_at')
          .order('full_name', ascending: true);
      final membersData = List<Map<String, dynamic>>.from(membersRes);

      // 2. Récupération des transactions
      final transRes = await _supabase
          .from('transactions')
          .select('id, amount, currency, category, type, description, created_at, user_id, status')
          .order('created_at', ascending: false);
      final transData = List<Map<String, dynamic>>.from(transRes);

      // 3. Calcul du solde global (CDF et USD)
      double cdf = 0.0;
      double usd = 0.0;

      for (var item in transData) {
        final amount = (item['amount'] as num?)?.toDouble() ?? 0.0;
        final currency = (item['currency'] ?? 'CDF').toString().toUpperCase();
        final type = (item['type'] ?? 'INCOME').toString().toUpperCase();
        final status = item['status'] ?? 'APPROVED';

        if (status == 'APPROVED') {
          if (currency == 'USD' || currency == '\$') {
            usd += (type == 'INCOME' || type == 'ENTREE' || type == 'COTISATION') ? amount : -amount;
          } else {
            cdf += (type == 'INCOME' || type == 'ENTREE' || type == 'COTISATION') ? amount : -amount;
          }
        }
      }

      // 4. Calcul des retards de paiement par membre
      List<Map<String, dynamic>> lateList = [];
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);

      for (var member in membersData) {
        final String memberId = member['id'].toString();
        final String memberName = member['full_name'] ?? member['username'] ?? 'Membre';

        final DateTime memberCreation = DateTime.tryParse(member['created_at'] ?? '') ?? now;
        final startDate = DateTime(memberCreation.year, memberCreation.month, memberCreation.day);

        // Jours écoulés depuis la création du compte
        int totalDaysExpected = today.difference(startDate).inDays + 1;
        if (totalDaysExpected < 1) totalDaysExpected = 1;

        // Somme des cotisations journalières payées
        double totalPaidForDaily = 0.0;
        final memberTxList = transData.where((t) => t['user_id'].toString() == memberId).toList();

        for (var tx in memberTxList) {
          final category = (tx['category'] ?? '').toString().toLowerCase();
          final status = (tx['status'] ?? 'APPROVED').toString().toUpperCase();

          if (status == 'APPROVED' && (category.contains('journali') || category.contains('daily'))) {
            totalPaidForDaily += (tx['amount'] as num?)?.toDouble() ?? 0.0;
          }
        }

        int daysCovered = (totalPaidForDaily / _dailyTargetCDF).floor();
        int lateDays = totalDaysExpected - daysCovered;

        if (lateDays > 0) {
          double debtAmount = lateDays * _dailyTargetCDF;
          lateList.add({
            'member_id': memberId,
            'name': memberName,
            'late_days': lateDays,
            'debt_amount': debtAmount,
          });
        }
      }

      if (mounted) {
        setState(() {
          _membersList = membersData;
          _recentTransactions = transData.where((t) => t['status'] == 'APPROVED').take(30).toList();
          _lateMembersList = lateList;
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

  Future<void> _deleteTransaction(String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Supprimer ?"),
        content: const Text("Voulez-vous vraiment effacer cette transaction ?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Non")),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Oui, Effacer")),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await _supabase.from('transactions').delete().eq('id', id);
        _showSnackBar("Transaction supprimée", Colors.orange);
        _loadCaisseData(showLoader: false);
      } catch (e) {
        _showSnackBar("Erreur : $e", Colors.redAccent);
      }
    }
  }

  void _showEditTransactionDialog(Map<String, dynamic> tx) {
    final amountController = TextEditingController(text: tx['amount'].toString());
    final descController = TextEditingController(text: tx['description'] ?? '');
    String selectedCurrency = tx['currency'] ?? 'CDF';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Modifier Transaction"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: amountController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "Montant")),
            DropdownButtonFormField<String>(
              value: selectedCurrency,
              items: const [DropdownMenuItem(value: 'CDF', child: Text("CDF")), DropdownMenuItem(value: 'USD', child: Text("USD"))],
              onChanged: (v) => selectedCurrency = v ?? 'CDF',
            ),
            TextField(controller: descController, decoration: const InputDecoration(labelText: "Description")),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Annuler")),
          ElevatedButton(
            onPressed: () async {
              try {
                await _supabase.from('transactions').update({
                  'amount': double.tryParse(amountController.text) ?? 0,
                  'currency': selectedCurrency,
                  'description': descController.text,
                }).eq('id', tx['id']);
                Navigator.pop(ctx);
                _showSnackBar("Mise à jour réussie", Colors.green);
                _loadCaisseData(showLoader: false);
              } catch (e) {
                _showSnackBar("Erreur : $e", Colors.redAccent);
              }
            },
            child: const Text("Sauvegarder"),
          ),
        ],
      ),
    );
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

  Future<void> _exportHistoryToPDF() async {
    final pdf = pw.Document();
    final fmtUSD = NumberFormat('#,##0.00', 'fr_FR');
    final fmtCDF = NumberFormat('#,##0', 'fr_FR');

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) => [
          pw.Header(level: 0, text: "HISTORIQUE DE CAISSE - COMITÉ ISLAMIQUE"),
          pw.Divider(),
          pw.Text("Solde Global USD : ${fmtUSD.format(_totalUSD)} \$"),
          pw.Text("Solde Global CDF : ${fmtCDF.format(_totalCDF)} FC"),
          pw.SizedBox(height: 20),
          pw.TableHelper.fromTextArray(
            headers: ['Date', 'Type', 'Montant', 'Catégorie', 'Statut'],
            data: _recentTransactions.map((tx) {
              final date = DateTime.parse(tx['created_at']).toLocal();
              return [
                DateFormat('dd/MM/yy').format(date),
                tx['type'] == 'INCOME' ? 'ENTRÉE' : 'SORTIE',
                "${tx['amount']} ${tx['currency']}",
                tx['category'] ?? '-',
                tx['status'] ?? '-'
              ];
            }).toList(),
          ),
        ],
      ),
    );

    await Printing.layoutPdf(onLayout: (PdfPageFormat format) async => pdf.save());
  }

  /// Dialogue pour enregistrer une nouvelle cotisation ou apurer une dette
  void _showAddContributionDialog({String? preselectedUserId, double? suggestedAmount}) {
    String? selectedUserId = preselectedUserId;
    final amountController = TextEditingController(
      text: suggestedAmount != null ? suggestedAmount.toStringAsFixed(0) : "500",
    );
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
                    // Champ de recherche du membre
                    TextFormField(
                      controller: searchController,
                      decoration: const InputDecoration(
                        labelText: "Rechercher un membre",
                        prefixIcon: Icon(Icons.search, size: 20),
                        isDense: true,
                      ),
                      onChanged: (val) {
                        setDialogState(() {});
                      },
                    ),
                    const SizedBox(height: 10),

                    // Sélection dynamique du membre via le menu déroulant filtré
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
                            if (v.contains('500') && suggestedAmount == null) amountController.text = "500";
                            if (v.contains('2000') && suggestedAmount == null) amountController.text = "2000";
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
                    noteController.dispose();
                    searchController.dispose();
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
                    searchController.dispose();
                    Navigator.pop(context);

                    try {
                      final currentUser = _supabase.auth.currentUser;

                      // Insertion sécurisée dans la table transactions
                      await _supabase.from('transactions').insert({
                        'user_id': selectedUserId,
                        'amount': amount,
                        'currency': selectedCurrency,
                        'type': 'INCOME',
                        'category': selectedType,
                        'description': noteText.isEmpty ? 'Cotisation enregistrée' : noteText,
                        'status': 'APPROVED',
                        'approved_by': currentUser?.id,
                        'approved_at': DateTime.now().toIso8601String(),
                        'created_at': DateTime.now().toIso8601String(),
                      });

                      // Notification automatique de confirmation
                      try {
                        await _supabase.from('notifications').insert({
                          'user_id': selectedUserId,
                          'title': '💰 Cotisation Enregistrée',
                          'message': 'Paiement de $amount $selectedCurrency ($selectedType) bien enregistré.',
                          'type': 'PAYMENT',
                          'created_at': DateTime.now().toIso8601String(),
                        });
                      } catch (_) {}

                      if (mounted) {
                        _showSnackBar("Cotisation enregistrée avec succès !", const Color(0xFF0F766E));
                        _loadCaisseData(); // Recharge pour effacer les retards si réglés
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
        title: Text("Espace Caissier", style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 18)),
        backgroundColor: const Color(0xFF0F766E),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf),
            tooltip: "Exporter Historique",
            onPressed: _isLoading ? null : _exportHistoryToPDF,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadCaisseData,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF0F766E)))
          : RefreshIndicator(
        onRefresh: _loadCaisseData,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Carte globale des soldes (Matching design Image 3)
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
                    Text("Solde Global de Caisse", style: GoogleFonts.poppins(color: Colors.white70, fontSize: 13)),
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

              // SECTION : ALERTES DE RETARDS DE PAIEMENT
              if (_lateMembersList.isNotEmpty) ...[
                Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 20),
                    const SizedBox(width: 6),
                    Text(
                      "Retards de paiement (${_lateMembersList.length})",
                      style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.redAccent),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _lateMembersList.length,
                  itemBuilder: (context, index) {
                    final item = _lateMembersList[index];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF2F2),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFFCA5A5)),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item['name'],
                                  style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 13, color: const Color(0xFF991B1B)),
                                ),
                                Text(
                                  "${item['late_days']} jour(s) en retard • Dette : ${item['debt_amount'].toStringAsFixed(0)} FC",
                                  style: GoogleFonts.poppins(fontSize: 11, color: const Color(0xFFB91C1C)),
                                ),
                              ],
                            ),
                          ),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFDC2626),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            ),
                            onPressed: () {
                              _showAddContributionDialog(
                                preselectedUserId: item['member_id'],
                                suggestedAmount: item['debt_amount'],
                              );
                            },
                            child: Text("Régler", style: GoogleFonts.poppins(fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                    );
                  },
                ),
                const SizedBox(height: 15),
              ],

              // HISTORIQUE DES TRANSACTIONS
              Text("Historique des transactions", style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
              const SizedBox(height: 10),

              _recentTransactions.isEmpty
                  ? Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                child: Center(child: Text("Aucune transaction trouvée.", style: GoogleFonts.poppins(color: Colors.grey))),
              )
                  : ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _recentTransactions.length,
                itemBuilder: (context, index) {
                  final item = _recentTransactions[index];
                  final amount = item['amount'] ?? 0;
                  final currency = item['currency'] ?? 'CDF';
                  final category = item['category'] ?? 'Cotisation';

                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    elevation: 1,
                    child: ListTile(
                      leading: const CircleAvatar(
                        backgroundColor: Color(0x1A0F766E),
                        child: Icon(Icons.arrow_downward, color: Color(0xFF0F766E), size: 20),
                      ),
                      title: Text(category, style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 13)),
                      subtitle: Text(
                        item['created_at'] != null ? item['created_at'].toString().split('T')[0] : '',
                        style: GoogleFonts.poppins(fontSize: 11),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            "+$amount $currency",
                            style: GoogleFonts.poppins(fontWeight: FontWeight.bold, color: const Color(0xFF0F766E), fontSize: 14),
                          ),
                          // Boutons d'édition réservés à l'admin
                          if (_isAdmin)
                            PopupMenuButton<String>(
                              onSelected: (val) {
                                if (val == 'edit') _showEditTransactionDialog(item);
                                if (val == 'delete') _deleteTransaction(item['id']);
                              },
                              itemBuilder: (ctx) => [
                                const PopupMenuItem(value: 'edit', child: Text("Modifier")),
                                const PopupMenuItem(value: 'delete', child: Text("Supprimer", style: TextStyle(color: Colors.red))),
                              ],
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
        onPressed: () => _showAddContributionDialog(),
        backgroundColor: const Color(0xFF0F766E),
        icon: const Icon(Icons.add_card, color: Colors.white),
        label: Text("Nouveau Paiement", style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
    );
  }
}
