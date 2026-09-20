-- 1. CRÉATION DU BUCKET STORAGE POUR LES PHOTOS (Si non existant)
-- Note: Supabase ne permet pas de créer des buckets via SQL pur facilement sans extensions.
-- Il est recommandé de le créer manuellement dans le tableau de bord Supabase (Storage -> New Bucket -> 'avatars' (public)).

-- 2. POLITIQUES DE SÉCURITÉ POUR LE STORAGE (Bucket 'avatars')
-- Autoriser tout le monde à lire les photos
-- Autoriser les utilisateurs connectés à uploader leurs propres photos

-- 3. POLITIQUES DE SÉCURITÉ POUR LES TRANSACTIONS (CRUD ADMIN)
-- L'admin peut supprimer et modifier les transactions
DROP POLICY IF EXISTS "Admins manage all transactions" ON public.transactions;
CREATE POLICY "Admins manage all transactions" ON public.transactions
FOR ALL TO authenticated USING (
    (SELECT role FROM public.profiles WHERE id = auth.uid()) = 'ADMIN'
);

-- 4. POLITIQUES DE SÉCURITÉ POUR LE CHAT (CRUD ADMIN)
-- L'admin peut supprimer les messages
DROP POLICY IF EXISTS "Admins can delete messages" ON public.chat_messages;
CREATE POLICY "Admins can delete messages" ON public.chat_messages
FOR DELETE TO authenticated USING (
    (SELECT role FROM public.profiles WHERE id = auth.uid()) = 'ADMIN'
);

-- 5. S'assurer que les membres peuvent voir le total global (Déjà fait normalement, mais par sécurité)
DROP POLICY IF EXISTS "Enable read access for all transactions" ON public.transactions;
CREATE POLICY "Enable read access for all transactions" ON public.transactions
FOR SELECT TO authenticated USING (true);
