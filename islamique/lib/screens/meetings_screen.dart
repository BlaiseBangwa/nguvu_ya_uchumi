import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MeetingsScreen extends StatefulWidget {
  final bool isAdmin;
  const MeetingsScreen({Key? key, this.isAdmin = false}) : super(key: key);

  @override
  State<MeetingsScreen> createState() => _MeetingsScreenState();
}

class _MeetingsScreenState extends State<MeetingsScreen> {
  final SupabaseClient _supabase = Supabase.instance.client;
  bool _isLoading = true;
  List<Map<String, dynamic>> _meetings = [];
  Map<String, List<Map<String, dynamic>>> _attendeesMap = {};
  Set<String> _myAttendances = {};

  @override
  void initState() {
    super.initState();
    _loadMeetings();
  }

  Future<void> _loadMeetings() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final currentUserId = _supabase.auth.currentUser?.id;

      // 1. Récupérer toutes les réunions triées de la plus récente à la plus ancienne
      final meetingsRes = await _supabase
          .from('meetings')
          .select()
          .order('meeting_date', ascending: false);

      // 2. Récupérer toutes les présences enregistrées avec les profils
      final attendancesRes = await _supabase
          .from('meeting_attendances')
          .select('meeting_id, user_id, profiles(full_name, username)');

      Map<String, List<Map<String, dynamic>>> attendeesTemp = {};
      Set<String> myAttendancesTemp = {};

      for (var item in attendancesRes) {
        final mId = item['meeting_id'] as String;
        final uId = item['user_id'] as String;

        if (!attendeesTemp.containsKey(mId)) {
          attendeesTemp[mId] = [];
        }
        if (item['profiles'] != null) {
          attendeesTemp[mId]?.add(item['profiles']);
        }

        if (uId == currentUserId) {
          myAttendancesTemp.add(mId);
        }
      }

      if (mounted) {
        setState(() {
          _meetings = List<Map<String, dynamic>>.from(meetingsRes);
          _attendeesMap = attendeesTemp;
          _myAttendances = myAttendancesTemp;
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

  // Marquer / Décommander sa présence (Réservé aux Membres non-admin)
  Future<void> _toggleAttendance(String meetingId) async {
    final currentUserId = _supabase.auth.currentUser?.id;
    if (currentUserId == null) return;

    final isPresent = _myAttendances.contains(meetingId);

    try {
      if (isPresent) {
        await _supabase
            .from('meeting_attendances')
            .delete()
            .eq('meeting_id', meetingId)
            .eq('user_id', currentUserId);

        if (mounted) _showSnackBar("Présence retirée", Colors.orange);
      } else {
        await _supabase.from('meeting_attendances').insert({
          'meeting_id': meetingId,
          'user_id': currentUserId,
          'status': 'PRESENT',
        });

        if (mounted) _showSnackBar("Présence confirmée avec succès !", Colors.green);
      }
      _loadMeetings();
    } catch (e) {
      if (mounted) _showSnackBar("Erreur : ${e.toString()}", Colors.redAccent);
    }
  }

  // Supprimer une réunion (Pour Administrateur)
  Future<void> _deleteMeeting(String meetingId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text("Annuler cette réunion ?", style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
        content: const Text("Voulez-vous vraiment supprimer cette réunion de l'ordre du jour ?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text("Non", style: GoogleFonts.poppins(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text("Oui, Supprimer", style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await _supabase.from('meetings').delete().eq('id', meetingId);
        if (mounted) _showSnackBar("Réunion supprimée", Colors.orange);
        _loadMeetings();
      } catch (e) {
        if (mounted) _showSnackBar("Erreur de suppression : ${e.toString()}", Colors.redAccent);
      }
    }
  }

  // Dialogue de création de Réunion
  void _showCreateMeetingDialog() {
    final titleController = TextEditingController();
    final locationController = TextEditingController(text: "Siège de l'association");
    DateTime selectedDate = DateTime.now().add(const Duration(days: 1));
    TimeOfDay selectedTime = const TimeOfDay(hour: 10, minute: 0);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Text("Programmer une Réunion", style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 18)),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: titleController,
                      decoration: const InputDecoration(
                        labelText: "Titre de la réunion *",
                        hintText: "ex: Assemblée Générale",
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: locationController,
                      decoration: const InputDecoration(labelText: "Lieu"),
                    ),
                    const SizedBox(height: 16),

                    // Sélection de la date
                    ListTile(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      tileColor: Colors.grey.shade100,
                      leading: const Icon(Icons.calendar_month, color: Color(0xFF0F766E)),
                      title: Text(
                        "${selectedDate.day}/${selectedDate.month}/${selectedDate.year}",
                        style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                      ),
                      subtitle: const Text("Cliquez pour choisir le jour"),
                      onTap: () async {
                        final pickedDate = await showDatePicker(
                          context: context,
                          initialDate: selectedDate,
                          firstDate: DateTime.now(),
                          lastDate: DateTime.now().add(const Duration(days: 365)),
                        );
                        if (pickedDate != null) {
                          setDialogState(() => selectedDate = pickedDate);
                        }
                      },
                    ),
                    const SizedBox(height: 8),

                    // Sélection de l'heure
                    ListTile(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      tileColor: Colors.grey.shade100,
                      leading: const Icon(Icons.access_time, color: Color(0xFF0F766E)),
                      title: Text(
                        selectedTime.format(context),
                        style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                      ),
                      subtitle: const Text("Cliquez pour choisir l'heure"),
                      onTap: () async {
                        final pickedTime = await showTimePicker(
                          context: context,
                          initialTime: selectedTime,
                        );
                        if (pickedTime != null) {
                          setDialogState(() => selectedTime = pickedTime);
                        }
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    titleController.dispose();
                    locationController.dispose();
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
                    final title = titleController.text.trim();
                    final location = locationController.text.trim();

                    if (title.isEmpty) {
                      _showSnackBar("Veuillez saisir un titre", Colors.orange);
                      return;
                    }

                    final finalDateTime = DateTime(
                      selectedDate.year,
                      selectedDate.month,
                      selectedDate.day,
                      selectedTime.hour,
                      selectedTime.minute,
                    );

                    titleController.dispose();
                    locationController.dispose();
                    Navigator.pop(context);

                    try {
                      // 1. Enregistrer la réunion
                      await _supabase.from('meetings').insert({
                        'title': title,
                        'location': location,
                        'meeting_date': finalDateTime.toIso8601String(),
                      });

                      // 2. Déclencher une notification automatique
                      final formattedDate =
                          "${finalDateTime.day}/${finalDateTime.month}/${finalDateTime.year} à ${finalDateTime.hour}h${finalDateTime.minute.toString().padLeft(2, '0')}";

                      try {
                        await _supabase.from('notifications').insert({
                          'title': '📅 Nouvelle Réunion Programmée',
                          'message': 'Une réunion "$title" aura lieu le $formattedDate au lieu : $location.',
                          'type': 'MEETING',
                          'created_at': DateTime.now().toIso8601String(),
                        });
                      } catch (_) {
                        // Table des notifications optionnelle
                      }

                      if (mounted) {
                        _showSnackBar("Réunion publiée et notification envoyée !", Colors.green);
                        _loadMeetings();
                      }
                    } catch (e) {
                      if (mounted) _showSnackBar("Erreur lors de la création : ${e.toString()}", Colors.redAccent);
                    }
                  },
                  child: Text("Créer & Notifier", style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
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

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();

    return Scaffold(
      appBar: AppBar(
        title: Text("Réunions & Ordre du jour", style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 18)),
        backgroundColor: const Color(0xFF0F766E),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: "Actualiser",
            onPressed: _isLoading ? null : _loadMeetings,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF0F766E)))
          : _meetings.isEmpty
          ? Center(
        child: Text("Aucune réunion programmée", style: GoogleFonts.poppins(color: Colors.grey)),
      )
          : RefreshIndicator(
        onRefresh: _loadMeetings,
        child: ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: _meetings.length,
          itemBuilder: (context, index) {
            final meeting = _meetings[index];
            final String mId = meeting['id'];
            final bool isAttending = _myAttendances.contains(mId);
            final List<Map<String, dynamic>> attendees = _attendeesMap[mId] ?? [];
            final DateTime meetingDate = DateTime.parse(meeting['meeting_date']);

            // Vérifier si la réunion est expirée
            final bool isExpired = meetingDate.isBefore(now);

            return Card(
              margin: const EdgeInsets.only(bottom: 16),
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // En-tête : Titre et Badges
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                meeting['title'] ?? 'Réunion',
                                style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: isExpired ? Colors.red.shade100 : Colors.green.shade100,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  isExpired ? "🔴 Réunion Expirée / Terminée" : "🟢 Réunion À venir",
                                  style: GoogleFonts.poppins(
                                    color: isExpired ? Colors.red.shade800 : Colors.green.shade800,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0F766E).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            "${meetingDate.day}/${meetingDate.month}/${meetingDate.year}\n${meetingDate.hour}h${meetingDate.minute.toString().padLeft(2, '0')}",
                            textAlign: TextAlign.center,
                            style: GoogleFonts.poppins(
                              color: const Color(0xFF0F766E),
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // Lieu
                    Row(
                      children: [
                        const Icon(Icons.location_on_outlined, size: 16, color: Colors.grey),
                        const SizedBox(width: 4),
                        Text(
                          meeting['location'] ?? 'Lieu non spécifié',
                          style: GoogleFonts.poppins(color: Colors.grey[700], fontSize: 13),
                        ),
                      ],
                    ),
                    const Divider(height: 24),

                    // Section Présence
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          "${attendees.length} Membre(s) présent(s)",
                          style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.blueGrey),
                        ),

                        // Boutons réservés aux MEMBRES SIMPLES (Non-Admin)
                        if (!widget.isAdmin)
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: isExpired
                                  ? Colors.grey.shade300
                                  : (isAttending ? Colors.green : const Color(0xFF0F766E)),
                              foregroundColor: isExpired ? Colors.grey.shade600 : Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            onPressed: isExpired ? null : () => _toggleAttendance(mId),
                            icon: Icon(
                              isAttending ? Icons.check_circle : Icons.person_add_alt_1,
                              size: 18,
                            ),
                            label: Text(
                              isExpired
                                  ? "Terminée"
                                  : (isAttending ? "Présence confirmée" : "Je serai présent"),
                              style: GoogleFonts.poppins(fontSize: 12),
                            ),
                          ),

                        // Bouton de suppression réservé à l'ADMINISTRATEUR
                        if (widget.isAdmin)
                          IconButton(
                            icon: const Icon(Icons.delete_outline, color: Colors.red),
                            tooltip: "Supprimer la réunion",
                            onPressed: () => _deleteMeeting(mId),
                          ),
                      ],
                    ),

                    // Liste visuelle des membres inscrits
                    if (attendees.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: attendees.map((a) {
                          return Chip(
                            avatar: CircleAvatar(
                              backgroundColor: const Color(0xFF0F766E),
                              child: Text(
                                (a['full_name'] ?? 'M')[0].toUpperCase(),
                                style: const TextStyle(color: Colors.white, fontSize: 10),
                              ),
                            ),
                            label: Text(
                              a['full_name'] ?? a['username'] ?? '',
                              style: GoogleFonts.poppins(fontSize: 11),
                            ),
                            backgroundColor: Colors.grey[100],
                          );
                        }).toList(),
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        ),
      ),
      floatingActionButton: widget.isAdmin
          ? FloatingActionButton.extended(
        onPressed: _showCreateMeetingDialog,
        backgroundColor: const Color(0xFF0F766E),
        icon: const Icon(Icons.add_task, color: Colors.white),
        label: Text("Nouvelle Réunion", style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.bold)),
      )
          : null,
    );
  }
}