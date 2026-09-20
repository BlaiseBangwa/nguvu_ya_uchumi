# Analyse de Conformité au Cahier des Charges

Cette analyse compare les fonctionnalités actuelles de l'application avec les exigences spécifiées dans le document "CAHIER DE CHARGES APPLICATION MOBILE GESTION DE TONTINE".

## État des Fonctionnalités

### 1. Authentification & Rôles
- [x] **Connexion par Pseudo/Mot de passe** : Implémenté.
- [x] **Rôles (Admin, Caissier, Collecteur, Membre)** : Implémenté et fonctionnel.

### 2. Espace Administrateur (Admin)
- [x] **Montant Global** : Affiché sur le dashboard.
- [/] **Gestion des Utilisateurs (CRUD)** :
    - [x] Création, modification de rôle et suppression fonctionnelles.
    - [ ] **MANQUANT** : Champs "Date de naissance" et "État civil" dans le formulaire de création.
    - [ ] **MANQUANT** : ID membre lisible (ex: MBR-001) non stocké explicitement.
- [ ] **Statistiques Groupées** : Manque la vue par âge (mineur, adulte, vieux) et état civil.
- [ ] **Statut En Ligne** : Pas d'indicateur pour voir qui est connecté.
- [ ] **Gestion des Dépenses** : Pas d'interface pour saisir les dépenses (uniquement l'affichage dans les rapports).
- [ ] **Suggestions** : Pas d'espace pour lire ou supprimer les suggestions des membres.
- [ ] **Export PDF** : Manque le bouton pour télécharger les rapports journaliers/semestriels.

### 3. Espace Caissier
- [x] **Approbation des Paiements** : Implémenté via l'écran Caisse.
- [x] **Montant Global** : Affiché.
- [ ] **Export PDF** : Manque le bouton de téléchargement.
- [ ] **Suggestions** : Pas d'espace dédié.

### 4. Espace Collecteur
- [x] **Collecte sur terrain** : Implémenté (Nouveau recouvrement).
- [x] **Double Validation** : Le workflow PENDING (Collecteur) -> APPROVED (Caissier) est respecté.

### 5. Espace Membre
- [x] **Rapports personnels** : Cotisations validées et en attente affichées.
- [x] **Historique** : Liste des versements disponible.
- [ ] **Suggestions** : Pas d'interface pour envoyer des propositions.
- [ ] **Alertes de retard** : Pas de système automatique détectant les retards de paiement.

### 6. Général & Technique
- [x] **Base de données** : Supabase (PostgreSQL) utilisé comme suggéré.
- [x] **Gestion Hors-ligne** : `NetworkHelper` implémenté pour les erreurs réseau.
- [ ] **Photo de profil** : Option non disponible dans l'interface.

---

## Liste des "Clicks" (Boutons/Interactions) Manquants

> [!WARNING]
> Voici les éléments d'interface qu'il faudrait ajouter pour être 100% conforme :

1.  **Bouton "Télécharger PDF"** : Dans les écrans de rapports et de caisse.
2.  **Bouton "Ajouter une Dépense"** : Dans l'espace Admin.
3.  **Onglet/Bouton "Suggestions"** : Pour permettre aux membres d'écrire et à l'admin de lire.
4.  **Champs Supplémentaires (Formulaire User)** : Date de naissance (DatePicker) et Menu déroulant État Civil.
5.  **Indicateur Visuel "En Ligne"** : Une pastille verte sur la liste des membres pour l'admin.
6.  **Bouton "Photo de profil"** : Dans les paramètres ou le profil pour uploader une image.

---

## Prochaines étapes suggérées
1.  **Corriger l'importation défectueuse** détectée dans `collecteur_dashboard.dart` (`package0google_fonts`).
2.  **Prioriser l'ajout du formulaire complet** de création de membre (Date naissance/État civil) car cela bloque les statistiques futures.
3.  **Implémenter le système de suggestions** simple (Table Supabase + Interface).
