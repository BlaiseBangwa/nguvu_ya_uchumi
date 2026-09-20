import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'database_helper.dart';

class SyncService {
  final SupabaseClient supabase = Supabase.instance.client;

  Future<void> syncLocalToCloud() async {
    final List<ConnectivityResult> connectivityResult =
    await (Connectivity().checkConnectivity());

    if (connectivityResult.contains(ConnectivityResult.none) ||
        connectivityResult.isEmpty) {
      return; // Hors-ligne : aucune action
    }

    final db = DatabaseHelper.instance;

    try {
      List<Map<String, dynamic>> unsyncedContributions =
      await db.getUnsyncedContributions();

      for (var item in unsyncedContributions) {
        try {
          var dataToUpload = Map<String, dynamic>.from(item);

          // Nettoyage des clés purement locales avant envoi Supabase
          dataToUpload.remove('synced');

          // Alignement avec la table 'transactions' utilisée par le Dashboard
          await supabase.from('transactions').upsert(dataToUpload);

          // Marquage comme synchronisé dans SQLite
          await db.markContributionAsSynced(item['id'].toString());
        } catch (e) {
          debugPrint("Erreur de synchronisation pour l'élément ${item['id']}: $e");
        }
      }
    } catch (e) {
      debugPrint("Erreur globale lors de la synchronisation : $e");
    }
  }
}