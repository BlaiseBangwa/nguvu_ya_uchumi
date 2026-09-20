-- ========================================================
-- SCRIPT DE CONFIGURATION TOTALE ET RÉPARATION (PROD)
-- À exécuter dans le SQL Editor de Supabase
-- ========================================================

-- 1. RÉPARATION DES RÔLES (Supprimer les blocages)
ALTER TABLE public.profiles DROP CONSTRAINT IF EXISTS profiles_role_check;

-- 2. MISE À JOUR DE LA STRUCTURE DES TABLES
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS gender TEXT;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS birth_date DATE;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS marital_status TEXT;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS phone TEXT;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS address TEXT;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS activity TEXT;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS is_approved BOOLEAN DEFAULT true;

-- 3. ACTIVATION DU TEMPS RÉEL (REALTIME)
-- Cela permet aux soldes et messages de s'afficher sans rafraîchir
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
        CREATE PUBLICATION supabase_realtime;
    END IF;
END $$;

-- Ajouter les tables à la publication Realtime
ALTER PUBLICATION supabase_realtime ADD TABLE public.transactions;
ALTER PUBLICATION supabase_realtime ADD TABLE public.profiles;
ALTER PUBLICATION supabase_realtime ADD TABLE public.chat_messages;
ALTER PUBLICATION supabase_realtime ADD TABLE public.meetings;

-- 4. POLITIQUES DE SÉCURITÉ (RLS) - FIX POUR COLLECTEURS ET ADMINS
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.transactions ENABLE ROW LEVEL SECURITY;

-- Autoriser les Admins à TOUT faire
DROP POLICY IF EXISTS "Admins manage all profiles" ON public.profiles;
CREATE POLICY "Admins manage all profiles" ON public.profiles
FOR ALL TO authenticated USING (
    (SELECT role FROM public.profiles WHERE id = auth.uid()) = 'ADMIN'
);

DROP POLICY IF EXISTS "Admins manage all transactions" ON public.transactions;
CREATE POLICY "Admins manage all transactions" ON public.transactions
FOR ALL TO authenticated USING (
    (SELECT role FROM public.profiles WHERE id = auth.uid()) = 'ADMIN'
);

-- Autoriser tout membre connecté à voir les transactions (pour le temps réel et les totaux)
DROP POLICY IF EXISTS "Enable read access for all transactions" ON public.transactions;
CREATE POLICY "Enable read access for all transactions" ON public.transactions
FOR SELECT TO authenticated USING (true);

-- 5. INITIALISATION DE L'ADMIN PRINCIPAL
-- Remplacez 'admin' par votre pseudo si différent
UPDATE public.profiles
SET role = 'ADMIN', is_approved = true
WHERE username = 'admin';
