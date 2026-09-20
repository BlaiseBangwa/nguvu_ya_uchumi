import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({Key? key}) : super(key: key);

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  final SupabaseClient _supabase = Supabase.instance.client;
  bool _isLoading = true;

  int _totalMembers = 0;
  int _approvedMembers = 0;

  // Statistiques démographiques
  int _mineurs = 0;
  int _adultes = 0;
  int _vieux = 0;
  Map<String, int> _maritalStats = {};

  // Gestion bidevise
  double _totalIncomeUSD = 0.0;
  double _totalExpenseUSD = 0.0;
  double _totalIncomeCDF = 0.0;
  double _totalExpenseCDF = 0.0;

  @override
  void initState() {
    super.initState();
    _fetchReportData();
  }

  Future<void> _fetchReportData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      // 1. Inscriptions membres
      final profilesRes = await _supabase.from('profiles').select('is_approved, birth_date, marital_status');
      final profilesList = List<Map<String, dynamic>>.from(profilesRes);

      int totalUsers = profilesList.length;
      int approvedUsers = profilesList.where((u) => u['is_approved'] == true).length;

      int min = 0, adu = 0, vux = 0;
      Map<String, int> mar = {};

      for (var u in profilesList) {
        String s = u['marital_status'] ?? 'Non spécifié';
        mar[s] = (mar[s] ?? 0) + 1;

        if (u['birth_date'] != null) {
          try {
            final b = DateTime.parse(u['birth_date']);
            final age = DateTime.now().year - b.year;
            if (age < 18) min++;
            else if (age <= 55) adu++;
            else vux++;
          } catch (_) {}
        }
      }

      // 2. Flux financiers approuvés
      final txRes = await _supabase
          .from('transactions')
          .select('amount, type, currency')
          .eq('status', 'APPROVED');

      final txList = List<Map<String, dynamic>>.from(txRes);

      double incomeUSD = 0.0;
      double expenseUSD = 0.0;
      double incomeCDF = 0.0;
      double expenseCDF = 0.0;

      for (var tx in txList) {
        double amt = (tx['amount'] as num?)?.toDouble() ?? 0.0;
        String currency = (tx['currency'] as String?)?.toUpperCase() ?? 'USD';

        if (currency == 'CDF' || currency == 'FC') {
          if (tx['type'] == 'INCOME') {
            incomeCDF += amt;
          } else if (tx['type'] == 'EXPENSE') {
            expenseCDF += amt;
          }
        } else {
          if (tx['type'] == 'INCOME') {
            incomeUSD += amt;
          } else if (tx['type'] == 'EXPENSE') {
            expenseUSD += amt;
          }
        }
      }

      if (mounted) {
        setState(() {
          _totalMembers = totalUsers;
          _approvedMembers = approvedUsers;
          _mineurs = min;
          _adultes = adu;
          _vieux = vux;
          _maritalStats = mar;
          _totalIncomeUSD = incomeUSD;
          _totalExpenseUSD = expenseUSD;
          _totalIncomeCDF = incomeCDF;
          _totalExpenseCDF = expenseCDF;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur de chargement: ${e.toString()}'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  Future<void> _exportToPDF() async {
    final pdf = pw.Document();
    final fmtUSD = NumberFormat('#,##0.00', 'fr_FR');
    final fmtCDF = NumberFormat('#,##0', 'fr_FR');

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text("RAPPORT FINANCIER GLOBAL", style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
            pw.Divider(),
            pw.Text("Généré le : ${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now())}"),
            pw.SizedBox(height: 20),
            pw.Text("STATISTIQUES MEMBRES", style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            pw.Bullet(text: "Total inscrits : $_totalMembers"),
            pw.Bullet(text: "Membres actifs : $_approvedMembers"),
            pw.Bullet(text: "Mineurs (<18 ans) : $_mineurs"),
            pw.Bullet(text: "Adultes (18-55 ans) : $_adultes"),
            pw.Bullet(text: "Vieux (>55 ans) : $_vieux"),
            pw.SizedBox(height: 20),
            pw.Text("BILAN FINANCIER", style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            pw.Text("Devise USD :"),
            pw.Bullet(text: "Total Entrées : ${fmtUSD.format(_totalIncomeUSD)} \$"),
            pw.Bullet(text: "Total Sorties : ${fmtUSD.format(_totalExpenseUSD)} \$"),
            pw.Bullet(text: "Solde Net : ${fmtUSD.format(_totalIncomeUSD - _totalExpenseUSD)} \$"),
            pw.SizedBox(height: 10),
            pw.Text("Devise CDF (FC) :"),
            pw.Bullet(text: "Total Entrées : ${fmtCDF.format(_totalIncomeCDF)} FC"),
            pw.Bullet(text: "Total Sorties : ${fmtCDF.format(_totalExpenseCDF)} FC"),
            pw.Bullet(text: "Solde Net : ${fmtCDF.format(_totalIncomeCDF - _totalExpenseCDF)} FC"),
          ],
        ),
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: 'Rapport_Tontine_${DateFormat('yyyyMMdd').format(DateTime.now())}.pdf',
    );
  }

  @override
  Widget build(BuildContext context) {
    final double netBalanceUSD = _totalIncomeUSD - _totalExpenseUSD;
    final double netBalanceCDF = _totalIncomeCDF - _totalExpenseCDF;

    final fmtUSD = NumberFormat('#,##0.00', 'fr_FR');
    final fmtCDF = NumberFormat('#,##0', 'fr_FR');

    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        title: Text(
          "Rapports & Statistiques",
          style: GoogleFonts.poppins(color: const Color(0xFF0F172A), fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Color(0xFF0F172A)),
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf),
            tooltip: "Exporter en PDF",
            onPressed: _isLoading ? null : _exportToPDF,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _fetchReportData,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF0F766E)))
          : RefreshIndicator(
        onRefresh: _fetchReportData,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text("Aperçu Membres", style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildMetricCard(
                    "Total Inscrits",
                    "$_totalMembers",
                    Icons.people,
                    Colors.indigo,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildMetricCard(
                    "Membres Actifs",
                    "$_approvedMembers",
                    Icons.check_circle,
                    Colors.green,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text("Par Tranche d'Âge", style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 14)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: _buildSmallStat("Mineurs", "$_mineurs", Colors.blue)),
                const SizedBox(width: 8),
                Expanded(child: _buildSmallStat("Adultes", "$_adultes", Colors.orange)),
                const SizedBox(width: 8),
                Expanded(child: _buildSmallStat("Séniors", "$_vieux", Colors.purple)),
              ],
            ),
            const SizedBox(height: 16),
            Text("Par État Civil", style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 14)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _maritalStats.entries.map((e) => _buildMaritalChip(e.key, e.value)).toList(),
            ),
            const SizedBox(height: 24),

            // Bilan Financier USD
            Text("Bilan Financier (USD)", style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 12),
            _buildFinancialRow("Entrées totales", "${fmtUSD.format(_totalIncomeUSD)} \$", Colors.green),
            const SizedBox(height: 8),
            _buildFinancialRow("Dépenses totales", "${fmtUSD.format(_totalExpenseUSD)} \$", Colors.red),
            const Divider(height: 20),
            _buildFinancialRow(
              "Solde Net USD",
              "${fmtUSD.format(netBalanceUSD)} \$",
              netBalanceUSD >= 0 ? const Color(0xFF0F766E) : Colors.red,
              isBold: true,
            ),

            const SizedBox(height: 24),

            // Bilan Financier CDF
            Text("Bilan Financier (CDF / FC)", style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 12),
            _buildFinancialRow("Entrées totales", "${fmtCDF.format(_totalIncomeCDF)} FC", Colors.green),
            const SizedBox(height: 8),
            _buildFinancialRow("Dépenses totales", "${fmtCDF.format(_totalExpenseCDF)} FC", Colors.red),
            const Divider(height: 20),
            _buildFinancialRow(
              "Solde Net CDF",
              "${fmtCDF.format(netBalanceCDF)} FC",
              netBalanceCDF >= 0 ? const Color(0xFF0F766E) : Colors.red,
              isBold: true,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 8),
          Text(value, style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.bold)),
          Text(title, style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey[600])),
        ],
      ),
    );
  }

  Widget _buildFinancialRow(String title, String amount, Color color, {bool isBold = false}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: GoogleFonts.poppins(fontWeight: isBold ? FontWeight.bold : FontWeight.normal)),
          Text(
            amount,
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.bold,
              fontSize: isBold ? 16 : 14,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSmallStat(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 5),
      decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
      child: Column(
        children: [
          Text(value, style: GoogleFonts.poppins(fontWeight: FontWeight.bold, color: color)),
          Text(label, style: GoogleFonts.poppins(fontSize: 10, color: color)),
        ],
      ),
    );
  }

  Widget _buildMaritalChip(String label, int count) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.grey.shade300)),
      child: Text("$label : $count", style: GoogleFonts.poppins(fontSize: 12)),
    );
  }
}
