import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/notification_service.dart';

import '../auth/login_screen.dart';
import 'chat_screen.dart';
import 'suggestions_screen.dart';
import '../meetings_screen.dart';

class MembreDashboard extends StatefulWidget {
  const MembreDashboard({Key? key}) : super(key: key);

  @override
  State<MembreDashboard> createState() => _MembreDashboardState();
}

class _MembreDashboardState extends State<MembreDashboard> {
  final SupabaseClient _supabase = Supabase.instance.client;
  bool _isLoading = true;

  double _myTotalCDF = 0.0;
  double _myTotalUSD = 0.0;
  double _pendingCDF = 0.0;
  double _pendingUSD = 0.0;
  double _totalInFC = 0.0; // Total converti au taux de 2500

  // Bilan Global Comité
  double _globalCDF = 0.0;
  double _globalUSD = 0.0;
  double _totalExpensesCDF = 0.0;
  double _totalExpensesUSD = 0.0;

  int _unreadMessagesCount = 0;
  int _upcomingMeetingsCount = 0;

  List<Map<String, dynamic>> _myHistory = [];
  StreamSubscription? _realtimeSubscription;

  @override
  void initState() {
    super.initState();
    _loadMembreData();
    _fetchNotificationBadges();
    _initRealtimeListener();
  }

  @override
  void dispose() {
    _realtimeSubscription?.cancel();
    super.dispose();
  }

  void _initRealtimeListener() {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;

    // Écoute les changements sur la table transactions pour cet utilisateur
    _realtimeSubscription = _supabase
        .from('transactions')
        .stream(primaryKey: ['id'])
        .eq('user_id', userId)
        .listen((_) {
      // Recharger les données dès qu'un changement (insertion, update, suppression) est détecté
      _loadMembreData(showLoader: false);
      _fetchNotificationBadges();
    });

    // Écouter aussi les nouveaux messages pour le badge
    _supabase
        .from('chat_messages')
        .stream(primaryKey: ['id'])
        .listen((_) => _fetchNotificationBadges());

    // Écouter les nouvelles réunions
    _supabase
        .from('meetings')
        .stream(primaryKey: ['id'])
        .listen((payload) {
      if (payload.isNotEmpty) {
        final lastMeeting = payload.last;
        final title = lastMeeting['title'] ?? 'Réunion';
        NotificationService.showNotification(
          id: 200,
          title: "Nouvelle Réunion",
          body: "La réunion '$title' a été programmée.",
        );
        _fetchNotificationBadges();
      }
    });
  }

  Future<void> _fetchNotificationBadges() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    try {
      // 1. Compter les messages non lus dans le chat global
      final query = _supabase.from('chat_messages').select('id');
      final response = await query.neq('user_id', user.id).eq('is_read', false);
      
      final int count = (response as List).length;

      // 2. Compter les réunions à venir
      final meetingQuery = _supabase.from('meetings').select('id');
      final meetingRes = await meetingQuery.gte('meeting_date', DateTime.now().toIso8601String());

      if (mounted) {
        setState(() {
          _unreadMessagesCount = count;
          _upcomingMeetingsCount = (meetingRes as List).length;
        });
      }
    } catch (_) {}
  }

  Future<void> _loadMembreData({bool showLoader = true}) async {
    if (!mounted) return;
    if (showLoader) setState(() => _isLoading = true);

    try {
      final userId = _supabase.auth.currentUser?.id;

      if (userId == null) {
        _showSnackBar("Session expirée. Veuillez vous reconnecter.", Colors.redAccent);
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      final historyRes = await _supabase
          .from('transactions')
          .select()
          .order('created_at', ascending: false);

      final historyList = List<Map<String, dynamic>>.from(historyRes as List);

      // 1. Calculs personnels
      double approvedCDF = 0.0;
      double approvedUSD = 0.0;
      double pendingCDF = 0.0;
      double pendingUSD = 0.0;

      // 2. Calculs globaux (Bilan)
      double gCdf = 0.0;
      double gUsd = 0.0;
      double eCdf = 0.0;
      double eUsd = 0.0;

      for (var item in historyList) {
        final double amount = (item['amount'] as num?)?.toDouble() ?? 0.0;
        final String currency = (item['currency'] as String?)?.toUpperCase() ?? 'USD';
        final String status = item['status'] ?? 'PENDING';
        final String type = (item['type'] ?? 'INCOME').toString().toUpperCase();
        final String txUserId = item['user_id']?.toString() ?? '';
        final isCDF = currency == 'CDF' || currency == 'FC';

        // Stats personnelles
        if (txUserId == userId) {
          if (status == 'APPROVED') {
            if (isCDF) approvedCDF += amount; else approvedUSD += amount;
          } else if (status == 'PENDING') {
            if (isCDF) pendingCDF += amount; else pendingUSD += amount;
          }
        }

        // Stats globales (validées uniquement)
        if (status == 'APPROVED') {
          if (type == 'INCOME' || type == 'COTISATION' || type == 'ENTREE') {
            if (isCDF) gCdf += amount; else gUsd += amount;
          } else if (type == 'EXPENSE' || type == 'DEPENSE' || type == 'SORTIE') {
            if (isCDF) eCdf += amount; else eUsd += amount;
          }
        }
      }

      if (mounted) {
        setState(() {
          _myTotalCDF = approvedCDF;
          _myTotalUSD = approvedUSD;
          _pendingCDF = pendingCDF;
          _pendingUSD = pendingUSD;
          _totalInFC = approvedCDF + (approvedUSD * 2500);

          _globalCDF = gCdf - eCdf;
          _globalUSD = gUsd - eUsd;
          _totalExpensesCDF = eCdf;
          _totalExpensesUSD = eUsd;

          _myHistory = historyList.where((t) => t['user_id'].toString() == userId).toList();
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

  // Helper pour formater les montants
  String _formatAmount(double amount, String currency) {
    final isCDF = currency.toUpperCase() == 'CDF' || currency.toUpperCase() == 'FC';
    return isCDF
        ? NumberFormat('#,##0', 'fr_FR').format(amount)
        : NumberFormat('#,##0.00', 'fr_FR').format(amount);
  }

  String _formatDate(String? isoString) {
    if (isoString == null || isoString.isEmpty) return "-";
    try {
      final dt = DateTime.parse(isoString).toLocal();
      return DateFormat('dd/MM/yyyy à HH:mm').format(dt);
    } catch (_) {
      return isoString.length >= 10 ? isoString.substring(0, 10) : isoString;
    }
  }

  // Boîte de dialogue des détails d'un versement
  void _showTransactionDetails(Map<String, dynamic> item) {
    final double amount = (item['amount'] as num?)?.toDouble() ?? 0.0;
    final currency = item['currency'] ?? 'USD';
    final category = item['category'] ?? 'Cotisation Hebdomadaire';
    final status = item['status'] ?? 'PENDING';
    final description = item['description'] ?? 'Aucune remarque spécifiée';
    final String dateFormatted = _formatDate(item['created_at']);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text("Détails du Versement", style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildDetailRow("Montant :", "${_formatAmount(amount, currency)} $currency"),
            _buildDetailRow("Catégorie :", category),
            _buildDetailRow("Statut :", status == 'APPROVED' ? 'Validé' : (status == 'PENDING' ? 'En attente' : 'Rejeté')),
            _buildDetailRow("Date :", dateFormatted),
            _buildDetailRow("Note :", description),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text("Fermer", style: GoogleFonts.poppins(color: const Color(0xFF0F766E), fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: RichText(
        text: TextSpan(
          style: GoogleFonts.poppins(color: Colors.black87, fontSize: 13),
          children: [
            TextSpan(text: "$label ", style: const TextStyle(fontWeight: FontWeight.bold)),
            TextSpan(text: value),
          ],
        ),
      ),
    );
  }

  Widget _buildGlobalStatItem(String label, String value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: GoogleFonts.poppins(fontSize: 10, color: Colors.grey.shade600)),
        Text(value, style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.bold, color: color)),
      ],
    );
  }

  // Confirmation et gestion de la déconnexion
  Future<void> _confirmSignOut() async {
    final bool? shouldSignOut = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text("Confirmation", style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
          content: Text("Voulez-vous vraiment vous déconnecter ?", style: GoogleFonts.poppins(fontSize: 14)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text("Annuler", style: GoogleFonts.poppins(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () => Navigator.of(context).pop(true),
              child: Text("Déconnexion", style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );

    if (shouldSignOut == true) {
      try {
        await _supabase.auth.signOut();
        if (mounted) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (context) => const LoginScreen()),
                (route) => false,
          );
        }
      } catch (e) {
        if (mounted) _showSnackBar("Erreur lors de la déconnexion : ${e.toString()}", Colors.redAccent);
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

  @override
  Widget build(BuildContext context) {
    final bool hasPending = _pendingUSD > 0 || _pendingCDF > 0;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text("Mon Espace Tontine", style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 18)),
        backgroundColor: const Color(0xFF0F766E),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          // Bouton Réunions avec Badge
          Stack(
            alignment: Alignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.event_available),
                tooltip: "Réunions & Présence",
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const MeetingsScreen(isAdmin: false)),
                  ).then((_) => _fetchNotificationBadges());
                },
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

          // Bouton Chat avec Badge
          Stack(
            alignment: Alignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.chat_bubble_outline),
                tooltip: "Espace Discussion",
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const ChatScreen()),
                  ).then((_) => _fetchNotificationBadges());
                },
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
            onPressed: _isLoading
                ? null
                : () {
              _loadMembreData();
              _fetchNotificationBadges();
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white),
            tooltip: "Déconnexion",
            onPressed: _confirmSignOut,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF0F766E)))
          : RefreshIndicator(
        onRefresh: () async {
          await _loadMembreData();
          await _fetchNotificationBadges();
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Carte Totaux Multi-devises
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F766E),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF0F766E).withOpacity(0.3),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    )
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          "Cotisations Validées",
                          style: GoogleFonts.poppins(color: Colors.white70, fontSize: 13),
                        ),
                        const Icon(Icons.verified, color: Colors.white70, size: 20),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text("USD", style: GoogleFonts.poppins(color: Colors.white70, fontSize: 11)),
                            Text(
                              "${_formatAmount(_myTotalUSD, 'USD')} \$",
                              style: GoogleFonts.poppins(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        Container(height: 30, width: 1, color: Colors.white24),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text("CDF / FC", style: GoogleFonts.poppins(color: Colors.white70, fontSize: 11)),
                            Text(
                              "${_formatAmount(_myTotalCDF, 'CDF')} FC",
                              style: GoogleFonts.poppins(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const Divider(color: Colors.white24, height: 25),
                    Text(
                      "VALEUR TOTALE (Taux 1\u0024 = 2500 FC)",
                      style: GoogleFonts.poppins(color: Colors.white60, fontSize: 10, letterSpacing: 1),
                    ),
                    Text(
                      "${_formatAmount(_totalInFC, 'CDF')} FC",
                      style: GoogleFonts.poppins(color: Colors.amber.shade300, fontSize: 20, fontWeight: FontWeight.w800),
                    ),
                    if (hasPending) ...[
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          "En attente : ${_pendingUSD > 0 ? '${_formatAmount(_pendingUSD, 'USD')} \$' : ''}"
                              "${_pendingUSD > 0 && _pendingCDF > 0 ? ' | ' : ''}"
                              "${_pendingCDF > 0 ? '${_formatAmount(_pendingCDF, 'CDF')} FC' : ''}",
                          style: GoogleFonts.poppins(color: Colors.amber.shade200, fontSize: 12, fontWeight: FontWeight.w500),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // SECTION : BILAN GLOBAL DU COMITÉ
              Text(
                "Bilan Global du Comité",
                style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.bold, color: const Color(0xFF334155)),
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _buildGlobalStatItem("Fonds en Caisse", "${_formatAmount(_globalUSD, 'USD')} \$", Colors.green),
                        _buildGlobalStatItem("Total Dépenses", "${_formatAmount(_totalExpensesUSD, 'USD')} \$", Colors.redAccent),
                      ],
                    ),
                    const Divider(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _buildGlobalStatItem("Fonds (FC)", "${_formatAmount(_globalCDF, 'CDF')} FC", Colors.green),
                        _buildGlobalStatItem("Dépenses (FC)", "${_formatAmount(_totalExpensesCDF, 'CDF')} FC", Colors.redAccent),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Titre Historique
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    "Historique des versements",
                    style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.bold, color: const Color(0xFF334155)),
                  ),
                  Text(
                    "${_myHistory.length} entrée(s)",
                    style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade600),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Liste de l'historique
              _myHistory.isEmpty
                  ? Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Column(
                  children: [
                    Icon(Icons.history, size: 40, color: Colors.grey.shade400),
                    const SizedBox(height: 8),
                    Text(
                      "Aucun versement enregistré pour le moment.",
                      style: GoogleFonts.poppins(color: Colors.grey, fontSize: 13),
                    ),
                  ],
                ),
              )
                  : ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _myHistory.length,
                itemBuilder: (context, index) {
                  final item = _myHistory[index];
                  final String status = item['status'] ?? 'PENDING';
                  final double amount = (item['amount'] as num?)?.toDouble() ?? 0.0;
                  final currency = item['currency'] ?? 'USD';
                  final String formattedDate = _formatDate(item['created_at']);

                  final bool isApproved = status == 'APPROVED';
                  final bool isRejected = status == 'REJECTED';

                  return Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 1,
                    child: ListTile(
                      onTap: () => _showTransactionDetails(item),
                      leading: CircleAvatar(
                        backgroundColor: isApproved
                            ? Colors.green.shade100
                            : (isRejected ? Colors.red.shade100 : Colors.amber.shade100),
                        child: Icon(
                          isApproved
                              ? Icons.check_circle_outline
                              : (isRejected ? Icons.highlight_off : Icons.hourglass_top),
                          color: isApproved
                              ? Colors.green
                              : (isRejected ? Colors.red : Colors.amber.shade900),
                          size: 20,
                        ),
                      ),
                      title: Text(
                        "${_formatAmount(amount, currency)} $currency",
                        style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item['category'] ?? 'Cotisation Hebdomadaire',
                            style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade700),
                          ),
                          Text(
                            formattedDate,
                            style: GoogleFonts.poppins(fontSize: 11, color: Colors.grey.shade500),
                          ),
                        ],
                      ),
                      trailing: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: isApproved
                              ? Colors.green.shade50
                              : (isRejected ? Colors.red.shade50 : Colors.amber.shade50),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          isApproved ? 'Validé' : (isRejected ? 'Rejeté' : 'En attente'),
                          style: GoogleFonts.poppins(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: isApproved
                                ? Colors.green.shade800
                                : (isRejected ? Colors.red.shade800 : Colors.amber.shade900),
                          ),
                        ),
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
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => SuggestionsScreen(isAdmin: false)),
        ),
        backgroundColor: const Color(0xFF0F766E),
        icon: const Icon(Icons.lightbulb_outline, color: Colors.white),
        label: Text("Suggestion",
            style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
    );
  }
}
