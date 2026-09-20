import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';

class SettingsPage extends StatefulWidget {
  final bool isAdmin;

  const SettingsPage({super.key, this.isAdmin = false});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final SupabaseClient _supabase = Supabase.instance.client;
  bool _notificationsEnabled = true;
  bool _isUploading = false;
  String? _photoUrl;
  String? _fullName;

  User? get _currentUser => _supabase.auth.currentUser;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final user = _currentUser;
    if (user == null) return;
    try {
      final res = await _supabase.from('profiles').select('photo_url, full_name').eq('id', user.id).maybeSingle();
      if (mounted && res != null) {
        setState(() {
          _photoUrl = res['photo_url'];
          _fullName = res['full_name'];
        });
      }
    } catch (_) {}
  }

  Future<void> _pickAndUploadImage() async {
    final picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery, imageQuality: 50);

    if (image == null) return;

    setState(() => _isUploading = true);

    try {
      final user = _currentUser;
      if (user == null) return;

      final fileFile = File(image.path);
      final fileExt = image.path.split('.').last;
      final fileName = '${user.id}_${DateTime.now().millisecondsSinceEpoch}.$fileExt';
      final filePath = fileName;

      // Upload vers Supabase Storage (Bucket 'avatars')
      await _supabase.storage.from('avatars').upload(
        filePath,
        fileFile,
        fileOptions: const FileOptions(cacheControl: '3600', upsert: false),
      );

      // Récupérer l'URL publique
      final String publicUrl = _supabase.storage.from('avatars').getPublicUrl(filePath);

      // Mettre à jour le profil
      await _supabase.from('profiles').update({'photo_url': publicUrl}).eq('id', user.id);

      if (mounted) {
        setState(() {
          _photoUrl = publicUrl;
          _isUploading = false;
        });
        _showSnackBar("Photo de profil mise à jour !", Colors.green);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isUploading = false);
        _showSnackBar("Erreur upload : ${e.toString()}", Colors.redAccent);
      }
    }
  }

  // Boîte de dialogue pour changer son propre mot de passe via Supabase
  Future<void> _showChangePasswordDialog() async {
    final newPasswordController = TextEditingController();
    final confirmPasswordController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    bool isUpdating = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Text(
                'Changer le mot de passe',
                style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 18),
              ),
              content: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: newPasswordController,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Nouveau mot de passe *',
                        prefixIcon: Icon(Icons.lock_outline),
                        border: OutlineInputBorder(),
                      ),
                      validator: (val) {
                        if (val == null || val.trim().isEmpty) {
                          return 'Saisissez un nouveau mot de passe';
                        }
                        if (val.trim().length < 6) {
                          return 'Au moins 6 caractères requis';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: confirmPasswordController,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Confirmer le mot de passe *',
                        prefixIcon: Icon(Icons.lock_reset),
                        border: OutlineInputBorder(),
                      ),
                      validator: (val) {
                        if (val != newPasswordController.text) {
                          return 'Les mots de passe ne correspondent pas';
                        }
                        return null;
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isUpdating ? null : () => Navigator.pop(ctx),
                  child: Text('Annuler', style: GoogleFonts.poppins(color: Colors.grey)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0F766E),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: isUpdating
                      ? null
                      : () async {
                    final state = formKey.currentState;
                    if (state != null && state.validate()) {
                      setDialogState(() => isUpdating = true);
                      try {
                        await _supabase.auth.updateUser(
                          UserAttributes(password: newPasswordController.text.trim()),
                        );

                        if (mounted) {
                          Navigator.pop(ctx);
                          _showSnackBar(
                            "Mot de passe mis à jour avec succès !",
                            Colors.green,
                          );
                        }
                      } catch (e) {
                        setDialogState(() => isUpdating = false);
                        if (mounted) {
                          _showSnackBar("Erreur : ${e.toString()}", Colors.redAccent);
                        }
                      }
                    }
                  },
                  child: isUpdating
                      ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                  )
                      : Text('Mettre à jour', style: GoogleFonts.poppins(color: Colors.white)),
                ),
              ],
            );
          },
        );
      },
    );

    newPasswordController.dispose();
    confirmPasswordController.dispose();
  }

  // Déconnexion explicite de la session Supabase
  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("Déconnexion", style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
        content: const Text("Voulez-vous vraiment vous déconnecter de votre compte ?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Annuler"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Déconnexion", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _supabase.auth.signOut();
      if (mounted) {
        Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
      }
    }
  }

  void _showSnackBar(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: GoogleFonts.poppins()),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final String userEmail = _currentUser?.email ?? 'Utilisateur non connecté';

    return Scaffold(
      appBar: AppBar(
        title: Text('Paramètres du système', style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF0F766E),
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          // En-tête : Informations Profil Utilisateur
          Card(
            elevation: 1,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: ListTile(
              leading: CircleAvatar(
                radius: 25,
                backgroundColor: const Color(0xFF0F766E),
                backgroundImage: _photoUrl != null ? CachedNetworkImageProvider(_photoUrl!) : null,
                child: _photoUrl == null
                    ? Text(
                  userEmail.isNotEmpty ? userEmail[0].toUpperCase() : 'U',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                )
                    : null,
              ),
              title: Text(
                _fullName ?? userEmail,
                style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              subtitle: Text(
                widget.isAdmin ? 'Administrateur Principal' : 'Membre du Comité',
                style: GoogleFonts.poppins(
                  color: widget.isAdmin ? const Color(0xFF0F766E) : Colors.blueGrey,
                  fontWeight: FontWeight.w500,
                  fontSize: 12,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Modification du mot de passe
          ListTile(
            leading: const Icon(Icons.person_outline, color: Color(0xFF0F766E)),
            title: Text('Ma Photo de Profil', style: GoogleFonts.poppins(fontWeight: FontWeight.w500)),
            subtitle: Text(_isUploading ? 'Chargement en cours...' : 'Ajouter ou changer ma photo', style: GoogleFonts.poppins(fontSize: 12)),
            trailing: _isUploading
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.add_a_photo_outlined, size: 20),
            onTap: _isUploading ? null : _pickAndUploadImage,
          ),
          const Divider(),

          // Modification du mot de passe
          ListTile(
            leading: const Icon(Icons.lock_outline, color: Color(0xFF0F766E)),
            title: Text('Sécurité & Accès', style: GoogleFonts.poppins(fontWeight: FontWeight.w500)),
            subtitle: Text('Changer mon mot de passe', style: GoogleFonts.poppins(fontSize: 12)),
            trailing: const Icon(Icons.chevron_right),
            onTap: _showChangePasswordDialog,
          ),
          const Divider(),

          // Gestion des notifications
          SwitchListTile(
            secondary: const Icon(Icons.notifications_outlined, color: Color(0xFF0F766E)),
            title: Text('Notifications', style: GoogleFonts.poppins(fontWeight: FontWeight.w500)),
            subtitle: Text('Recevoir les alertes de gestion et de caisse', style: GoogleFonts.poppins(fontSize: 12)),
            value: _notificationsEnabled,
            activeColor: const Color(0xFF0F766E),
            onChanged: (bool value) {
              setState(() {
                _notificationsEnabled = value;
              });
              _showSnackBar(
                value ? "Notifications activées" : "Notifications désactivées",
                Colors.blueGrey,
              );
            },
          ),
          const Divider(),

          // Langue
          ListTile(
            leading: const Icon(Icons.language, color: Color(0xFF0F766E)),
            title: Text('Langue de l\'application', style: GoogleFonts.poppins(fontWeight: FontWeight.w500)),
            subtitle: Text('Français (Défaut)', style: GoogleFonts.poppins(fontSize: 12)),
          ),
          const Divider(),

          // Déconnexion
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.redAccent),
            title: Text(
              'Se déconnecter',
              style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: Colors.redAccent),
            ),
            onTap: _logout,
          ),
          const Divider(),

          // À propos
          const SizedBox(height: 20),
          Center(
            child: Column(
              children: [
                Text(
                  'Application De cotisation',
                  style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.grey[700]),
                ),
                Text(
                  'Designed by FAMIB • Version 1.0.0',
                  style: GoogleFonts.poppins(fontSize: 11, color: Colors.grey[500]),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}