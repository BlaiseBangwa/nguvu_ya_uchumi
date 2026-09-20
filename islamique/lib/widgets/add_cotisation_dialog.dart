import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class MemberOption {
  final String id;
  final String fullName;

  MemberOption({required this.id, required this.fullName});
}

class AddCotisationDialog extends StatefulWidget {
  final Function(Map<String, dynamic> cotisationData)? onSave;
  final List<MemberOption>? membresList; // Liste d'objets membres avec leur ID Supabase

  const AddCotisationDialog({
    Key? key,
    this.onSave,
    this.membresList,
  }) : super(key: key);

  @override
  State<AddCotisationDialog> createState() => _AddCotisationDialogState();
}

class _AddCotisationDialogState extends State<AddCotisationDialog> {
  final _formKey = GlobalKey<FormState>();

  final TextEditingController _montantController = TextEditingController();
  final TextEditingController _membreNomController = TextEditingController();
  final TextEditingController _motifController = TextEditingController();

  String? _selectedMemberId;
  DateTime _selectedDate = DateTime.now();
  String _typeCotisation = 'Mensuelle';
  String _devise = 'USD';
  bool _isSubmitting = false;

  final List<String> _typesList = [
    'Mensuelle',
    'Exceptionnelle',
    'Inauguration',
    'Secours/Social',
    'Autre'
  ];

  final List<String> _devisesList = ['USD', 'CDF'];

  @override
  void dispose() {
    _montantController.dispose();
    _membreNomController.dispose();
    _motifController.dispose();
    super.dispose();
  }

  Future<void> _pickDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 30)),
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  Future<void> _submitForm() async {
    if (_isSubmitting) return;

    final currentState = _formKey.currentState;
    if (currentState != null && currentState.validate()) {
      setState(() => _isSubmitting = true);

      final double montant = double.parse(_montantController.text.trim());

      // Données structurées prêtes pour Supabase / Backend
      final data = {
        'user_id': _selectedMemberId, // Identifiant UUID Supabase
        'member_name': _selectedMemberId == null ? _membreNomController.text.trim() : null,
        'amount': montant,
        'currency': _devise,
        'type': _typeCotisation,
        'description': _motifController.text.trim(),
        'status': 'APPROVED', // Directement approuvé s'il s'agit d'une saisie administrative
        'created_at': _selectedDate.toIso8601String(),
      };

      try {
        if (widget.onSave != null) {
          await widget.onSave?.call(data);
        }
        if (mounted) {
          Navigator.of(context).pop(data);
        }
      } catch (e) {
        if (mounted) {
          setState(() => _isSubmitting = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("Erreur d'enregistrement : ${e.toString()}"),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool hasMembresList = widget.membresList != null && widget.membresList!.isNotEmpty;

    return AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16.0),
      ),
      title: Row(
        children: const [
          Icon(Icons.add_card, color: Color(0xFF0F766E)),
          SizedBox(width: 10),
          Text(
            'Nouvelle Cotisation',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: SizedBox(
          width: 420,
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 1. Sélection par ID ou Saisie Manuelle
                if (hasMembresList)
                  DropdownButtonFormField<String>(
                    value: _selectedMemberId,
                    decoration: const InputDecoration(
                      labelText: 'Sélectionner le Membre *',
                      prefixIcon: Icon(Icons.person),
                      border: OutlineInputBorder(),
                    ),
                    items: (widget.membresList ?? []).map((membre) {
                      return DropdownMenuItem<String>(
                        value: membre.id,
                        child: Text(membre.fullName),
                      );
                    }).toList(),
                    onChanged: (val) {
                      setState(() {
                        _selectedMemberId = val;
                      });
                    },
                    validator: (val) {
                      if (val == null || val.isEmpty) {
                        return 'Veuillez sélectionner un membre';
                      }
                      return null;
                    },
                  )
                else
                  TextFormField(
                    controller: _membreNomController,
                    decoration: const InputDecoration(
                      labelText: 'Nom complet du membre *',
                      prefixIcon: Icon(Icons.person),
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Le nom du membre est obligatoire';
                      }
                      if (value.trim().length < 2) {
                        return 'Entrez un nom valide';
                      }
                      return null;
                    },
                  ),

                const SizedBox(height: 16),

                // 2. Montant + Choix Strict de la Devise (USD / CDF)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 2,
                      child: TextFormField(
                        controller: _montantController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
                        ],
                        decoration: const InputDecoration(
                          labelText: 'Montant *',
                          prefixIcon: Icon(Icons.attach_money),
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Montant requis';
                          }
                          final parsed = double.tryParse(value);
                          if (parsed == null || parsed <= 0) {
                            return 'Montant doit être > 0';
                          }
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 1,
                      child: DropdownButtonFormField<String>(
                        value: _devise,
                        decoration: const InputDecoration(
                          labelText: 'Devise *',
                          border: OutlineInputBorder(),
                        ),
                        items: _devisesList.map((devise) {
                          return DropdownMenuItem(
                            value: devise,
                            child: Text(devise, style: const TextStyle(fontWeight: FontWeight.bold)),
                          );
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) setState(() => _devise = val);
                        },
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // 3. Type de Cotisation
                DropdownButtonFormField<String>(
                  value: _typeCotisation,
                  decoration: const InputDecoration(
                    labelText: 'Type de Cotisation *',
                    prefixIcon: Icon(Icons.category),
                    border: OutlineInputBorder(),
                  ),
                  items: _typesList.map((String type) {
                    return DropdownMenuItem<String>(
                      value: type,
                      child: Text(type),
                    );
                  }).toList(),
                  onChanged: (newValue) {
                    if (newValue != null) {
                      setState(() {
                        _typeCotisation = newValue;
                      });
                    }
                  },
                ),

                const SizedBox(height: 16),

                // 4. Date de Paiement
                InkWell(
                  onTap: () => _pickDate(context),
                  borderRadius: BorderRadius.circular(4),
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Date de paiement *',
                      prefixIcon: Icon(Icons.calendar_today),
                      border: OutlineInputBorder(),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          "${_selectedDate.day.toString().padLeft(2, '0')}/${_selectedDate.month.toString().padLeft(2, '0')}/${_selectedDate.year}",
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                        ),
                        const Icon(Icons.arrow_drop_down),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // 5. Motif / Note
                TextFormField(
                  controller: _motifController,
                  maxLines: 2,
                  decoration: InputDecoration(
                    labelText: _typeCotisation == 'Autre'
                        ? 'Motif de la cotisation (Obligatoire) *'
                        : 'Note / Observation (Optionnel)',
                    prefixIcon: const Icon(Icons.note),
                    border: const OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (_typeCotisation == 'Autre' && (value == null || value.trim().isEmpty)) {
                      return 'Veuillez préciser le motif pour le type "Autre"';
                    }
                    return null;
                  },
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
          child: const Text('Annuler', style: TextStyle(color: Colors.grey)),
        ),
        ElevatedButton(
          onPressed: _isSubmitting ? null : _submitForm,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF0F766E),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),-----------------------------------------------------------------------------------------------------------------------------------------------------------------------
            ),
          ),
          child: _isSubmitting
              ? const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
          )
              : const Text('Enregistrer', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }
}