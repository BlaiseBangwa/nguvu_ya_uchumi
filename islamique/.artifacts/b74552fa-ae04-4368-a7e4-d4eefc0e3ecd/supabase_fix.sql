-- 1. Mettre à jour tous les emails existants pour utiliser le nouveau suffixe @nguvu.app
-- Cela permettra à vos anciens comptes de fonctionner avec la nouvelle version de l'application.
UPDATE auth.users
SET email = split_part(email, '@', 1) || '@nguvu.app'
WHERE email LIKE '%@nguvu.local' OR email LIKE '%@app.internal';

-- 2. (OPTIONNEL) Si vous voulez réinitialiser le mot de passe d'un utilisateur spécifique (ex: 'admin')
-- Remplacez 'votre_nouveau_mot_de_passe' par le mot de passe souhaité.
-- UPDATE auth.users
-- SET encrypted_password = crypt('votre_nouveau_mot_de_passe', gen_salt('bf'))
-- WHERE email = 'admin@nguvu.app';

-- 3. (OPTIONNEL - ATTENTION) Si vous voulez tout supprimer pour recommencer à zéro proprement :
-- DELETE FROM auth.users;
-- DELETE FROM public.profiles;
-- DELETE FROM public.transactions;
