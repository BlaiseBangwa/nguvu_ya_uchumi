import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

class SuggestionsScreen extends StatefulWidget {
  final bool isAdmin;
  const SuggestionsScreen({super.key, this.isAdmin = false});

  @override
  State<SuggestionsScreen> createState() => _SuggestionsScreenState();
}

class _SuggestionsScreenState extends State<SuggestionsScreen> {
  final SupabaseClient _supabase = Supabase.instance.client;
  final TextEditingController _contentController = TextEditingController();
  bool _isLoading = false;
  List<Map<String, dynamic>> _suggestions = [];

  @override
  void initState() {
    super.initState();
    if (widget.isAdmin) {
      _loadSuggestions();
    }
  }

  Future<void> _loadSuggestions() async {
    setState(() => _isLoading = true);
    try {
      final res = await _supabase
          .from('suggestions')
          .select('*, profiles(full_name)')
          .order('created_at', ascending: false);
      setState(() => _suggestions = List<Map<String, dynamic>>.from(res));
    } catch (e) {
      _showSnackBar("Erreur de chargement : $e", Colors.redAccent);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _submitSuggestion() async {
    final content = _contentController.text.trim();
    if (content.isEmpty) return;

    setState(() => _isLoading = true);
    try {
      final userId = _supabase.auth.currentUser?.id;
      await _supabase.from('suggestions').insert({
        'user_id': userId,
        'content': content,
        'created_at': DateTime.now().toIso8601String(),
      });
      _contentController.clear();
      _showSnackBar("Suggestion envoyée avec succès !", Colors.green);
      if (!widget.isAdmin) {
        Navigator.pop(context);
      }
    } catch (e) {
      _showSnackBar("Erreur d'envoi : $e", Colors.redAccent);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _deleteSuggestion(String id) async {
    try {
      await _supabase.from('suggestions').delete().eq('id', id);
      _loadSuggestions();
      _showSnackBar("Suggestion supprimée", Colors.green);
    } catch (e) {
      _showSnackBar("Erreur : $e", Colors.redAccent);
    }
  }

  void _showSnackBar(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: color, behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isAdmin ? "Suggestions des Membres" : "Envoyer une Suggestion",
            style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF0F766E),
        foregroundColor: Colors.white,
      ),
      body: _isLoading && widget.isAdmin
          ? const Center(child: CircularProgressIndicator())
          : widget.isAdmin
              ? _buildAdminView()
              : _buildUserView(),
    );
  }

  Widget _buildUserView() {
    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Votre avis compte pour nous. N'hésitez pas à proposer des améliorations ou à partager vos préoccupations.",
            style: GoogleFonts.poppins(fontSize: 14, color: Colors.grey.shade700),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _contentController,
            maxLines: 6,
            decoration: InputDecoration(
              hintText: "Écrivez votre message ici...",
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _submitSuggestion,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0F766E),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: _isLoading
                  ? const CircularProgressIndicator(color: Colors.white)
                  : Text("Envoyer ma proposition",
                      style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAdminView() {
    if (_suggestions.isEmpty) {
      return Center(child: Text("Aucune suggestion pour le moment.", style: GoogleFonts.poppins()));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(10),
      itemCount: _suggestions.length,
      itemBuilder: (context, index) {
        final s = _suggestions[index];
        final profile = s['profiles'] as Map<String, dynamic>?;
        final date = DateTime.parse(s['created_at']);
        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: ListTile(
            title: Text(profile?['full_name'] ?? "Anonyme",
                style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 5),
                Text(s['content'] ?? ""),
                const SizedBox(height: 5),
                Text(DateFormat('dd/MM/yyyy HH:mm').format(date),
                    style: const TextStyle(fontSize: 10, color: Colors.grey)),
              ],
            ),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
              onPressed: () => _deleteSuggestion(s['id'].toString()),
            ),
          ),
        );
      },
    );
  }
}
