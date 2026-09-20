import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';
import 'user_details_screen.dart';

class ManageUsersScreen extends StatefulWidget {
  const ManageUsersScreen({Key? key}) : super(key: key);

  @override
  State<ManageUsersScreen> createState() => _ManageUsersScreenState();
}

class _ManageUsersScreenState extends State<ManageUsersScreen> {
  final SupabaseClient _supabase = Supabase.instance.client;
  bool _isLoading = true;
  List<Map<String, dynamic>> _users = [];
  List<Map<String, dynamic>> _filteredUsers = [];
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetchUsers();
  }

  /// Chargement des membres depuis Supabase
  Future<void> _fetchUsers() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final response = await _supabase
          .from('profiles')
          .select('id, full_name, username, role, phone, address, activity, gender, created_at, is_approved')
          .order('created_at', ascending: false);

      final List<Map<String, dynamic>> data = List<Map<String, dynamic>>.from(response as List);

      if (mounted) {
        setState(() {
          _users = data;
          _filteredUsers = data;
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

  void _filterUsers(String query) {
    if (query.isEmpty) {
      setState(() => _filteredUsers = _users);
    } else {
      final lowerQuery = query.toLowerCase();
      setState(() {
        _filteredUsers = _users.where((user) {
          final fullName = (user['full_name'] ?? '').toString().toLowerCase();
          final username = (user['username'] ?? '').toString().toLowerCase();
          final phone = (user['phone'] ?? '').toString().toLowerCase();
          return fullName.contains(lowerQuery) || username.contains(lowerQuery) || phone.contains(lowerQuery);
        }).toList();
      });
    }
  }

  void _showSnackBar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: GoogleFonts.poppins()),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  /// Dialogue d'ajout sécurisé
  void _showAddUserDialog() {
    final nameController = TextEditingController();
    final usernameController = TextEditingController();
    final passwordController = TextEditingController(text: "123456");
    final phoneController = TextEditingController();
    final addressController = TextEditingController();
    final activityController = TextEditingController();

    String selectedGender = 'M';
    String selectedRole = 'MEMBRE';
    String selectedMaritalStatus = 'Célibataire';
    DateTime? selectedBirthDate;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Row(
                children: [
                  const Icon(Icons.person_add, color: Color(0xFF0F766E)),
                  const SizedBox(width: 8),
                  Text("Nouveau Membre",
                      style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 16)),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: nameController,
                      decoration: const InputDecoration(
                        labelText: "Nom complet *",
                        prefixIcon: Icon(Icons.person),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: usernameController,
                      decoration: const InputDecoration(
                        labelText: "Pseudo / Identifiant *",
                        prefixIcon: Icon(Icons.alternate_email),
                      ),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      value: selectedGender,
                      decoration: const InputDecoration(
                        labelText: "Sexe / Genre *",
                        prefixIcon: Icon(Icons.wc),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'M', child: Text("Masculin (M)")),
                        DropdownMenuItem(value: 'F', child: Text("Féminin (F)")),
                      ],
                      onChanged: (val) {
                        if (val != null) setDialogState(() => selectedGender = val);
                      },
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: phoneController,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: "Numéro Téléphone *",
                        prefixIcon: Icon(Icons.phone),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: addressController,
                      decoration: const InputDecoration(
                        labelText: "Adresse / Quartier",
                        prefixIcon: Icon(Icons.location_on),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: activityController,
                      decoration: const InputDecoration(
                        labelText: "Activité / Profession",
                        prefixIcon: Icon(Icons.work),
                      ),
                    ),
                    const SizedBox(height: 10),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.cake, color: Color(0xFF0F766E)),
                      title: Text(
                        selectedBirthDate == null
                            ? "Date de naissance *"
                            : "Né le : ${DateFormat('dd/MM/yyyy').format(selectedBirthDate ?? DateTime.now())}",
                        style: GoogleFonts.poppins(fontSize: 14),
                      ),
                      subtitle: const Text("Cliquez pour choisir"),
                      onTap: () async {
                        final now = DateTime.now();
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: now.subtract(const Duration(days: 365 * 20)),
                          firstDate: DateTime(1920),
                          lastDate: now,
                        );
                        if (picked != null) {
                          setDialogState(() => selectedBirthDate = picked);
                        }
                      },
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      value: selectedMaritalStatus,
                      decoration: const InputDecoration(
                        labelText: "État Civil *",
                        prefixIcon: Icon(Icons.family_restroom),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'Célibataire', child: Text("Célibataire")),
                        DropdownMenuItem(value: 'Marié', child: Text("Marié")),
                        DropdownMenuItem(value: 'Divorcé', child: Text("Divorcé")),
                        DropdownMenuItem(value: 'Veuf', child: Text("Veuf(ve)")),
                      ],
                      onChanged: (val) {
                        if (val != null) setDialogState(() => selectedMaritalStatus = val);
                      },
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: passwordController,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: "Mot de passe initial *",
                        prefixIcon: Icon(Icons.lock),
                      ),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      value: selectedRole,
                      decoration: const InputDecoration(
                        labelText: "Rôle attribué",
                        prefixIcon: Icon(Icons.badge),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'MEMBRE', child: Text("MEMBRE")),
                        DropdownMenuItem(value: 'COLLECTEUR', child: Text("COLLECTEUR")),
                        DropdownMenuItem(value: 'TRESORIER', child: Text("TRESORIER")),
                        DropdownMenuItem(value: 'ADMIN', child: Text("ADMINISTRATEUR")),
                      ],
                      onChanged: (val) {
                        if (val != null) setDialogState(() => selectedRole = val);
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
                    final name = nameController.text.trim();
                    final username = usernameController.text.trim().toLowerCase();
                    final password = passwordController.text.trim();
                    final phone = phoneController.text.trim();
                    final address = addressController.text.trim();
                    final activity = activityController.text.trim();

                    if (name.isEmpty || username.isEmpty || password.isEmpty || phone.isEmpty || selectedBirthDate == null) {
                      _showSnackBar("Veuillez remplir les champs obligatoires (*)", Colors.orange);
                      return;
                    }

                    try {
                      // 1. Vérification du pseudo
                      final existing = await _supabase
                          .from('profiles')
                          .select('id')
                          .eq('username', username)
                          .maybeSingle();

                      if (existing != null) {
                        _showSnackBar("Le pseudo '$username' existe déjà.", Colors.orange);
                        return;
                      }

                      // 2. Création Auth sécurisée avec gestion du retour null
                      final fakeEmail = "$username@nguvu.app";
                      final AuthResponse res = await _supabase.auth.signUp(
                        email: fakeEmail,
                        password: password,
                        data: {
                          'full_name': name,
                          'username': username,
                          'role': selectedRole,
                        },
                      );

                      // Récupération sécurisée de l'ID utilisateur
                      final String? newId = res.user?.id;

                      if (newId != null && newId.isNotEmpty) {
                        // Insertion explicite du profil
                        await _supabase.from('profiles').upsert({
                          'id': newId,
                          'full_name': name,
                          'username': username,
                          'gender': selectedGender,
                          'phone': phone,
                          'address': address,
                          'activity': activity,
                          'birth_date': selectedBirthDate?.toIso8601String(),
                          'marital_status': selectedMaritalStatus,
                          'role': selectedRole,
                          'is_approved': true,
                          'created_at': DateTime.now().toIso8601String(),
                        });

                        if (mounted) {
                          Navigator.pop(context);
                          _showCredentialsDialog(username, password);
                          _fetchUsers();
                        }
                      } else {
                        // Si l'utilisateur est null (ex: email non confirmé ou bug session), 
                        // on tente de récupérer son profil créé par le déclencheur SQL
                        final profileCheck = await _supabase
                            .from('profiles')
                            .select('id')
                            .eq('username', username)
                            .maybeSingle();

                        if (profileCheck != null) {
                          if (mounted) {
                            Navigator.pop(context);
                            _showCredentialsDialog(username, password);
                            _fetchUsers();
                          }
                        } else {
                          throw Exception("L'utilisateur n'a pas pu être validé par Supabase.");
                        }
                      }
                    } catch (e) {
                      if (mounted) {
                        _showSnackBar("Erreur lors de la création : ${e.toString()}", Colors.redAccent);
                      }
                    }
                  },
                  child: Text("Créer",
                      style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// Modifier le rôle
  void _editUserRole(Map<String, dynamic> user) {
    String currentRole = (user['role'] ?? 'MEMBRE').toString().toUpperCase();
    String newRole = ['MEMBRE', 'COLLECTEUR', 'TRESORIER', 'ADMIN'].contains(currentRole)
        ? currentRole
        : 'MEMBRE';

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Text("Modifier le rôle", style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Membre : ${user['full_name'] ?? user['username']}",
                    style: GoogleFonts.poppins(fontSize: 13, color: Colors.grey.shade700),
                  ),
                  const SizedBox(height: 15),
                  DropdownButtonFormField<String>(
                    value: newRole,
                    decoration: const InputDecoration(labelText: "Rôle attribué"),
                    items: const [
                      DropdownMenuItem(value: 'MEMBRE', child: Text("MEMBRE")),
                      DropdownMenuItem(value: 'COLLECTEUR', child: Text("COLLECTEUR")),
                      DropdownMenuItem(value: 'TRESORIER', child: Text("TRESORIER")),
                      DropdownMenuItem(value: 'ADMIN', child: Text("ADMINISTRATEUR")),
                    ],
                    onChanged: (val) {
                      if (val != null) setDialogState(() => newRole = val);
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text("Annuler", style: GoogleFonts.poppins(color: Colors.grey)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0F766E)),
                  onPressed: () async {
                    Navigator.pop(context);
                    try {
                      await _supabase.from('profiles').update({'role': newRole}).eq('id', user['id']);
                      if (mounted) {
                        _showSnackBar("Rôle mis à jour !", Colors.green);
                        _fetchUsers();
                      }
                    } catch (e) {
                      if (mounted) {
                        _showSnackBar("Erreur : ${e.toString()}", Colors.redAccent);
                      }
                    }
                  },
                  child: Text("Enregistrer", style: GoogleFonts.poppins(color: Colors.white)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showCredentialsDialog(String pseudo, String pass) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text("Compte créé avec succès"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Veuillez communiquer ces identifiants au membre :"),
            const SizedBox(height: 15),
            Text("Pseudo : $pseudo", style: const TextStyle(fontWeight: FontWeight.bold)),
            Text("Mot de passe : $pass", style: const TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("OK")),
        ],
      ),
    );
  }

  Future<void> _toggleUserStatus(String id, bool currentStatus) async {
    try {
      await _supabase.from('profiles').update({'is_approved': !currentStatus}).eq('id', id);
      _fetchUsers();
      _showSnackBar(!currentStatus ? "Compte activé" : "Compte désactivé", Colors.blue);
    } catch (e) {
      _showSnackBar("Erreur : $e", Colors.redAccent);
    }
  }

  Future<void> _deleteUser(String id) async {
    try {
      await _supabase.from('profiles').delete().eq('id', id);
      if (mounted) {
        _showSnackBar("Membre supprimé", Colors.orange);
        _fetchUsers();
      }
    } catch (e) {
      _showSnackBar("Erreur de suppression : ${e.toString()}", Colors.redAccent);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text("Gestion des utilisateurs",
            style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 18)),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF0F172A),
        elevation: 0.5,
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _fetchUsers),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: TextField(
              controller: _searchController,
              onChanged: _filterUsers,
              decoration: InputDecoration(
                hintText: "Rechercher par nom, pseudo ou téléphone...",
                hintStyle: GoogleFonts.poppins(fontSize: 13),
                prefixIcon: const Icon(Icons.search, color: Color(0xFF0F766E)),
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: Color(0xFF0F766E)))
                : _filteredUsers.isEmpty
                ? Center(
                child: Text("Aucun utilisateur trouvé",
                    style: GoogleFonts.poppins(color: Colors.grey)))
                : ListView.builder(
              itemCount: _filteredUsers.length,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemBuilder: (context, index) {
                final user = _filteredUsers[index];
                final String role = (user['role'] ?? 'membre').toString().toUpperCase();
                final String phone = user['phone'] ?? '-';
                final String gender = user['gender'] ?? '';

                return Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                  color: Colors.white,
                  child: ListTile(
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => UserDetailsScreen(user: user))),
                    leading: Stack(
                      children: [
                        CircleAvatar(
                          backgroundColor: const Color(0x1A0F766E),
                          child: Text(
                            gender == 'F' ? '♀' : '♂',
                            style: GoogleFonts.poppins(
                                fontWeight: FontWeight.bold,
                                color: const Color(0xFF0F766E)),
                          ),
                        ),
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: (user['is_approved'] ?? true) ? Colors.green : Colors.grey, // Indique si actif
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 1.5),
                            ),
                          ),
                        ),
                      ],
                    ),
                    title: Text(
                      user['full_name'] ?? 'Sans Nom',
                      style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    subtitle: Text(
                      "Pseudo: ${user['username'] ?? '-'} • Tél: $phone\nRôle: $role",
                      style: GoogleFonts.poppins(fontSize: 11, color: Colors.grey.shade600),
                    ),
                    isThreeLine: true,
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: Icon(
                            (user['is_approved'] ?? true) ? Icons.block : Icons.check_circle_outline,
                            color: (user['is_approved'] ?? true) ? Colors.orange : Colors.green,
                            size: 20,
                          ),
                          tooltip: (user['is_approved'] ?? true) ? "Désactiver" : "Activer",
                          onPressed: () => _toggleUserStatus(user['id'], user['is_approved'] ?? true),
                        ),
                        IconButton(
                          icon: const Icon(Icons.edit, color: Colors.blue, size: 20),
                          onPressed: () => _editUserRole(user),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete, color: Colors.redAccent, size: 20),
                          onPressed: () => _deleteUser(user['id']),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddUserDialog,
        backgroundColor: const Color(0xFF0F766E),
        icon: const Icon(Icons.person_add, color: Colors.white),
        label: Text("Nouveau Membre",
            style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
    );
  }
}
