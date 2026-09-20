import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class UserDetailsScreen extends StatefulWidget {
  final Map<String, dynamic> user;
  const UserDetailsScreen({super.key, required this.user});

  @override
  State<UserDetailsScreen> createState() => _UserDetailsScreenState();
}

class _UserDetailsScreenState extends State<UserDetailsScreen> {
  final SupabaseClient _supabase = Supabase.instance.client;
  bool _isLoading = true;
  List<Map<String, dynamic>> _history = [];
  double _totalUSD = 0.0;
  double _totalCDF = 0.0;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    setState(() => _isLoading = true);
    try {
      final res = await _supabase
          .from('transactions')
          .select()
          .eq('user_id', widget.user['id'])
          .order('created_at', ascending: false);

      final data = List<Map<String, dynamic>>.from(res);
      double usd = 0;
      double cdf = 0;

      for (var tx in data) {
        if (tx['status'] == 'APPROVED') {
          double amt = (tx['amount'] as num?)?.toDouble() ?? 0.0;
          String cur = tx['currency'] ?? 'USD';
          if (cur == 'USD' || cur == '\$') usd += amt;
          else cdf += amt;
        }
      }

      setState(() {
        _history = data;
        _totalUSD = usd;
        _totalCDF = cdf;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _printUserReport() async {
    final pdf = pw.Document();
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (context) => [
          pw.Header(level: 0, text: "RELEVÉ INDIVIDUEL : ${widget.user['full_name']}"),
          pw.Text("Pseudo : ${widget.user['username']}"),
          pw.Text("Code Membre : ${widget.user['member_code'] ?? '-'}"),
          pw.Divider(),
          pw.SizedBox(height: 10),
          pw.Text("TOTAL VALIDÉ USD : ${_totalUSD.toStringAsFixed(2)} \$"),
          pw.Text("TOTAL VALIDÉ CDF : ${_totalCDF.toStringAsFixed(0)} FC"),
          pw.SizedBox(height: 20),
          pw.TableHelper.fromTextArray(
            headers: ['Date', 'Catégorie', 'Montant', 'Statut'],
            data: _history.map((tx) => [
              DateFormat('dd/MM/yy').format(DateTime.parse(tx['created_at'])),
              tx['category'] ?? '-',
              "${tx['amount']} ${tx['currency']}",
              tx['status'] ?? '-'
            ]).toList(),
          ),
        ],
      ),
    );
    await Printing.layoutPdf(onLayout: (format) async => pdf.save());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.user['full_name'] ?? "Détails Membre", style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF0F766E),
        foregroundColor: Colors.white,
        actions: [
          IconButton(icon: const Icon(Icons.print), onPressed: _printUserReport),
        ],
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator())
        : ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _buildInfoCard(),
              const SizedBox(height: 20),
              Text("Historique des activités", style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              ..._history.map((tx) => _buildTransactionItem(tx)).toList(),
            ],
          ),
    );
  }

  Widget _buildInfoCard() {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _smallStat("Total USD", "${_totalUSD.toStringAsFixed(1)} \$", Colors.green),
                _smallStat("Total CDF", "${_totalCDF.toStringAsFixed(0)} FC", Colors.blue),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _smallStat(String label, String val, Color color) {
    return Column(
      children: [
        Text(val, style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 18, color: color)),
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
      ],
    );
  }

  Widget _buildTransactionItem(Map<String, dynamic> tx) {
    final bool isApproved = tx['status'] == 'APPROVED';
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Text("${tx['amount']} ${tx['currency']}", style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text("${tx['category']} - ${DateFormat('dd/MM/yy').format(DateTime.parse(tx['created_at']))}"),
        trailing: Icon(isApproved ? Icons.check_circle : Icons.hourglass_empty, color: isApproved ? Colors.green : Colors.amber),
      ),
    );
  }
}
