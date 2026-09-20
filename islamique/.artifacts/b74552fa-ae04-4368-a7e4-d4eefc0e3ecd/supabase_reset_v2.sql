-- SCRIPT DE RÉINITIALISATION PROPRE (À copier dans Supabase SQL Editor)

-- 1. Vider les tables publiques (si elles existent)
DO $$
BEGIN
    IF EXISTS (SELECT FROM pg_tables WHERE schemaname = 'public' AND tablename = 'transactions') THEN
        TRUNCATE public.transactions CASCADE;
    END IF;
    IF EXISTS (SELECT FROM pg_tables WHERE schemaname = 'public' AND tablename = 'notifications') THEN
        TRUNCATE public.notifications CASCADE;
    END IF;
    IF EXISTS (SELECT FROM pg_tables WHERE schemaname = 'public' AND tablename = 'suggestions') THEN
        TRUNCATE public.suggestions CASCADE;
    END IF;
    IF EXISTS (SELECT FROM pg_tables WHERE schemaname = 'public' AND tablename = 'meetings') THEN
        TRUNCATE public.meetings CASCADE;
    END IF;
    IF EXISTS (SELECT FROM pg_tables WHERE schemaname = 'public' AND tablename = 'profiles') THEN
        TRUNCATE public.profiles CASCADE;
    END IF;
END $$;

-- 2. Supprimer tous les utilisateurs authentifiés
DELETE FROM auth.users;

-- ========================================================
-- COMMENT CRÉER VOTRE ADMIN APRÈS LE NETTOYAGE :
-- 1. Lancez l'application et inscrivez-vous normalement.
-- 2. Une fois inscrit, revenez ici et exécutez le code ci-dessous :
-- ========================================================

/*
UPDATE public.profiles
SET role = 'admin', is_approved = true
WHERE username = 'VOTRE_PSEUDO_ICI';
*/
