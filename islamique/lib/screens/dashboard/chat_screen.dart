import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/notification_service.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({Key? key}) : super(key: key);

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final SupabaseClient _supabase = Supabase.instance.client;
  final TextEditingController _msgController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  List<Map<String, dynamic>> _messages = [];
  bool _isLoading = true;
  bool _isSending = false;
  bool _isAdmin = false;
  RealtimeChannel? _chatChannel;

  @override
  void initState() {
    super.initState();
    _checkRole();
    _loadMessages();
    _setupRealtimeSubscription();
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
    _msgController.dispose();
    _scrollController.dispose();
    final channel = _chatChannel;
    if (channel != null) {
      _supabase.removeChannel(channel);
    }
    super.dispose();
  }

  // 1. Charger les messages et marquer les messages entrants comme LUS
  Future<void> _loadMessages() async {
    try {
      final response = await _supabase
          .from('chat_messages')
          .select('*, profiles(full_name, username)')
          .order('created_at', ascending: true);

      if (mounted) {
        setState(() {
          _messages = List<Map<String, dynamic>>.from(response as List);
          _isLoading = false;
        });
        _scrollToBottom();
        _markMessagesAsRead();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        _showSnackBar("Erreur lors du chargement des messages : ${e.toString()}", Colors.redAccent);
      }
    }
  }

  // Marquer tous les messages reçus non lus comme lus
  Future<void> _markMessagesAsRead() async {
    final currentUserId = _supabase.auth.currentUser?.id;
    if (currentUserId == null) return;

    try {
      await _supabase
          .from('chat_messages')
          .update({'is_read': true})
          .neq('user_id', currentUserId)
          .eq('is_read', false);
    } catch (_) {
      // Ignorer si la colonne is_read n'est pas encore configurée
    }
  }

  // 2. Écoute Temps Réel des Nouveaux Messages
  void _setupRealtimeSubscription() {
    final currentUserId = _supabase.auth.currentUser?.id;

    _chatChannel = _supabase
        .channel('public:chat_messages')
        .onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'chat_messages',
      callback: (payload) async {
        final newMsg = Map<String, dynamic>.from(payload.newRecord);
        final senderId = newMsg['user_id'];

        // Récupérer les détails du profil pour l'expéditeur
        Map<String, dynamic>? profile;
        try {
          final profileRes = await _supabase
              .from('profiles')
              .select('full_name, username')
              .eq('id', senderId)
              .maybeSingle();
          if (profileRes != null) {
            profile = Map<String, dynamic>.from(profileRes);
          }
        } catch (_) {}

        newMsg['profiles'] = profile;

        if (!mounted) return;

        setState(() {
          _messages.add(newMsg);
        });
        _scrollToBottom();

        final senderName = profile?['full_name'] ?? profile?['username'] ?? 'Un membre';

        if (senderId != currentUserId) {
          _showSnackBar("💬 $senderName : ${newMsg['message']}", const Color(0xFF0F766E));
          
          // Notification système (Son + Bannière)
          NotificationService.showNotification(
            id: DateTime.now().millisecond,
            title: "Nouveau message de $senderName",
            body: newMsg['message'] ?? '',
          );
          
          _markMessagesAsRead();
        }
      },
    )
        .subscribe();
  }

  // 3. Envoyer un message
  Future<void> _sendMessage() async {
    final text = _msgController.text.trim();
    if (text.isEmpty || _isSending) return;

    setState(() => _isSending = true);
    _msgController.clear();
    final currentUserId = _supabase.auth.currentUser?.id;

    if (currentUserId == null) {
      _showSnackBar("Session expirée. Veuillez vous reconnecter.", Colors.redAccent);
      setState(() => _isSending = false);
      return;
    }

    try {
      await _supabase.from('chat_messages').insert({
        'user_id': currentUserId,
        'message': text,
        'is_read': false,
      });
    } catch (e) {
      if (mounted) {
        _showSnackBar("Erreur d'envoi : ${e.toString()}", Colors.redAccent);
      }
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  Future<void> _deleteMessage(String id) async {
    try {
      await _supabase.from('chat_messages').delete().eq('id', id);
      setState(() {
        _messages.removeWhere((m) => m['id'] == id);
      });
      _showSnackBar("Message supprimé", Colors.orange);
    } catch (e) {
      _showSnackBar("Erreur : $e", Colors.redAccent);
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _showSnackBar(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: GoogleFonts.poppins()),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = _supabase.auth.currentUser?.id;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text("Espace de Discussion", style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 18)),
        backgroundColor: const Color(0xFF0F766E),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: "Actualiser",
            onPressed: _loadMessages,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: Color(0xFF0F766E)))
                : _messages.isEmpty
                ? Center(child: Text("Aucun message pour le moment", style: GoogleFonts.poppins(color: Colors.grey)))
                : ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final msg = _messages[index];
                final bool isMe = msg['user_id'] == currentUserId;
                final profile = msg['profiles'] as Map<String, dynamic>? ?? {};
                final bool isRead = msg['is_read'] ?? false;
                final DateTime? createdAt = msg['created_at'] != null
                    ? DateTime.tryParse(msg['created_at'])?.toLocal()
                    : null;

                return GestureDetector(
                  onLongPress: _isAdmin ? () => _deleteMessage(msg['id']) : null,
                  child: Align(
                    alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      constraints: BoxConstraints(
                        maxWidth: MediaQuery.of(context).size.width * 0.75,
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: isMe ? const Color(0xFF0F766E) : Colors.white,
                        borderRadius: BorderRadius.only(
                          topLeft: const Radius.circular(12),
                          topRight: const Radius.circular(12),
                          bottomLeft: Radius.circular(isMe ? 12 : 0),
                          bottomRight: Radius.circular(isMe ? 0 : 12),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.04),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          )
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                        children: [
                          Text(
                            profile['full_name'] ?? profile['username'] ?? 'Membre',
                            style: GoogleFonts.poppins(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: isMe ? Colors.white70 : Colors.teal.shade800,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            msg['message'] ?? '',
                            style: GoogleFonts.poppins(
                              color: isMe ? Colors.white : Colors.black87,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              if (createdAt != null)
                                Text(
                                  "${createdAt.hour.toString().padLeft(2, '0')}:${createdAt.minute.toString().padLeft(2, '0')}",
                                  style: TextStyle(
                                    fontSize: 9,
                                    color: isMe ? Colors.white60 : Colors.grey[600],
                                  ),
                                ),
                              if (isMe) ...[
                                const SizedBox(width: 4),
                                Icon(
                                  isRead ? Icons.done_all : Icons.check,
                                  size: 14,
                                  color: isRead ? Colors.lightBlueAccent : Colors.white60,
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _msgController,
                    style: GoogleFonts.poppins(fontSize: 14),
                    decoration: InputDecoration(
                      hintText: "Écrire un message...",
                      hintStyle: GoogleFonts.poppins(fontSize: 13, color: Colors.grey),
                      filled: true,
                      fillColor: Colors.grey.shade100,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    ),
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                const SizedBox(width: 8),
                CircleAvatar(
                  backgroundColor: const Color(0xFF0F766E),
                  child: _isSending
                      ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                  )
                      : IconButton(
                    icon: const Icon(Icons.send, color: Colors.white, size: 18),
                    onPressed: _sendMessage,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}