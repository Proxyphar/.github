# Étape 0a — Clé SSH d'administration

L'accès au VPS se fera **uniquement par clé SSH**. La clé privée reste sur le poste
d'administration ; seule la clé publique est déposée chez OVH puis sur le serveur.

Aucun mot de passe n'est demandé ni stocké dans ce dépôt.

## Générer la paire de clés (poste d'administration)

Sous Windows 10/11 (PowerShell), macOS ou Linux :

```bash
ssh-keygen -t ed25519 -a 100 -C "proxyphar-affichage-admin" -f ~/.ssh/proxyphar-affichage
```

- Choisissez une phrase de passe : elle protège la clé privée sur le poste.
- Deux fichiers sont créés :
  - `~/.ssh/proxyphar-affichage` : **clé privée**, à ne jamais copier ailleurs ;
  - `~/.ssh/proxyphar-affichage.pub` : **clé publique**, à déposer chez OVH.

Affichez la clé publique pour la copier :

```bash
cat ~/.ssh/proxyphar-affichage.pub
```

Elle ressemble à `ssh-ed25519 AAAAC3... proxyphar-affichage-admin` (une seule ligne).

## Déposer la clé publique dans le manager OVH

1. Manager OVHcloud > icône du compte (en haut à droite) > **Mon compte**.
2. Onglet **Clés SSH** > **Ajouter une clé SSH**.
3. Nom : `proxyphar-affichage-admin`. Collez la ligne complète de la clé publique. Validez.

Cette clé sera proposée lors de la réinstallation du VPS (étape 0b).

## Configurer le client SSH (facultatif mais recommandé)

Dans `~/.ssh/config` sur le poste d'administration :

```
Host affichage-proxyphar
    HostName 51.75.251.209
    User proxyadmin
    IdentityFile ~/.ssh/proxyphar-affichage
    IdentitiesOnly yes
```

Avant l'étape 2 (durcissement), l'utilisateur est celui indiqué dans l'e-mail de fin
de réinstallation OVH (`ubuntu` sur les images Ubuntu) ; après l'étape 2, c'est
`proxyadmin`.

## Sauvegarde de la clé

Conservez une copie chiffrée de la clé privée dans le coffre de mots de passe du service
(entrée « VPS Xibo PROXYPHAR — clé SSH »). En cas de perte, l'accès se récupère par une
nouvelle réinstallation ou par le mode rescue OVH : il n'y a pas de mot de passe de secours.
