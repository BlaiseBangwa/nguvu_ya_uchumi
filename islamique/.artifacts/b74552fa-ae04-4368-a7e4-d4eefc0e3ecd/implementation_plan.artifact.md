# Plan de Finalisation Finale : Notifications, CRUD et Bilan Global

Ce plan contient les toutes dernières finitions avant la livraison de la version 100% complète de l'application.

## Proposed Changes

### 1. Notifications "Heads-up" avec Son (Production)
#### [MODIFY] [admin_dashboard.dart](file:///C:/Users/Blaise/StudioProjects/gestionIslamique/islamique/lib/screens/dashboard/admin_dashboard.dart), [caissier_dashboard.dart](file:///C:/Users/Blaise/StudioProjects/gestionIslamique/islamique/lib/screens/dashboard/caissier_dashboard.dart), [membre_dashboard.dart](file:///C:/Users/Blaise/StudioProjects/gestionIslamique/islamique/lib/screens/dashboard/membre_dashboard.dart)
- Ajouter l'appel à `NotificationService` dans les écouteurs en temps réel (Realtime) pour les nouveaux messages et nouvelles réunions.
- Le téléphone sonnera et affichera une bannière même si l'utilisateur n'est pas sur l'écran spécifique.

### 2. Gestion Administrative Totale (CRUD)
#### [MODIFY] [caisse_screen.dart](file:///C:/Users/Blaise/StudioProjects/gestionIslamique/islamique/lib/screens/caisse_screen.dart)
- Ajouter un bouton de modification et suppression sur chaque transaction (visible uniquement pour l'ADMIN).
#### [MODIFY] [chat_screen.dart](file:///C:/Users/Blaise/StudioProjects/gestionIslamique/islamique/lib/screens/dashboard/chat_screen.dart)
- Permettre à l'ADMIN de supprimer un message par un appui long.

### 3. Photo de Profil (Pour Tous)
#### [MODIFY] [settings_page.dart](file:///C:/Users/Blaise/StudioProjects/gestionIslamique/islamique/lib/pages/settings_page.dart)
- Intégration de `image_picker` pour charger une photo depuis la galerie.
- Sauvegarde de l'image dans le bucket `avatars` de Supabase.

### 4. Bilan Global pour les Membres
#### [MODIFY] [membre_dashboard.dart](file:///C:/Users/Blaise/StudioProjects/gestionIslamique/islamique/lib/screens/dashboard/membre_dashboard.dart)
- Ajouter une section visuelle "Bilan de la Communauté" affichant :
    - Total cotisé (Entrées).
    - Total dépensé (Sorties).
    - Solde actuel restant en caisse.

## Verification Plan
1.  **Test Notification** : Envoyer un message -> Le téléphone doit sonner.
2.  **Test Admin** : Supprimer une transaction de test -> Le solde doit s'ajuster.
3.  **Test Photo** : Changer de photo -> Vérifier qu'elle s'affiche sur le dashboard.
