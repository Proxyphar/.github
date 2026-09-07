# Destination de sauvegarde : Object Storage OVHcloud (GRA)

Décision : les sauvegardes quotidiennes sont envoyées dans un conteneur **Object
Storage S3** OVHcloud, région **GRA** (Gravelines), dans le compte PROXYPHAR. Le
conteneur est distinct du VPS : une perte du VPS ne touche pas les sauvegardes.

## 1. Créer le conteneur (manager OVHcloud)

1. **Public Cloud** > sélectionner le projet, ou **Créer un projet** s'il n'en existe
   aucun (« PROXYPHAR Affichage »).
2. Menu **Storage** > **Object Storage** > **Créer un conteneur d'objets**.
3. Solution : **Standard Object Storage** (API S3). Région : **GRA**.
4. Nom du conteneur : `proxyphar-affichage-sauvegardes`. Conteneur **privé**.
5. Noter l'**endpoint S3** affiché sur la page du conteneur, de la forme
   `https://s3.gra.io.cloud.ovh.net`.

## 2. Créer l'utilisateur S3 (droits limités)

1. **Public Cloud** > **Project Management** > **Users & Roles** > **Créer un utilisateur**.
2. Description : `affichage-sauvegarde`. Rôle : **ObjectStore operator** uniquement.
3. Sur la ligne de cet utilisateur, menu `...` > **Générer des identifiants S3**.
   Noter l'**Access Key** et la **Secret Key** : la clé secrète n'est affichée qu'une fois.
4. Ranger les deux clés dans le coffre du service, entrée « Object Storage sauvegardes
   affichage ». Ne jamais les écrire dans un fichier du dépôt ni dans un e-mail.

## 3. Déclarer la destination sur le VPS

Sur le VPS, en root, une seule fois :

```bash
rclone config
```

Répondre : `n` (nouveau remote), nom `proxyphar-backup`, type `s3`, fournisseur `Other`,
`env_auth` : `false`, puis Access Key et Secret Key, région `gra`, endpoint
`s3.gra.io.cloud.ovh.net`, contrainte de localisation : laisser vide, ACL `private`,
puis accepter les valeurs par défaut jusqu'à `y` (confirmer) et `q` (quitter).

Le fichier `/root/.config/rclone/rclone.conf` contient les clés : vérifier ses droits.

```bash
chmod 600 /root/.config/rclone/rclone.conf
rclone lsd proxyphar-backup:
```

La dernière commande doit lister `proxyphar-affichage-sauvegardes`.

## 4. Activer la sauvegarde

```bash
/opt/affichage-kit/07-sauvegarde/installer-sauvegarde.sh --remote proxyphar-backup:proxyphar-affichage-sauvegardes/intranet --executer
```

Le script installe la minuterie, lance une première sauvegarde, puis un test de
restauration sur copie. Nettoyage ensuite :

```bash
/opt/affichage/bin/affichage-restore.sh --nettoyer
```

## 5. Contrôles et coûts

- Contenu de la destination : `rclone lsf --dirs-only proxyphar-backup:proxyphar-affichage-sauvegardes/intranet`
- Taille : `rclone size proxyphar-backup:proxyphar-affichage-sauvegardes`
- Facturation OVH au Go stocké et au trafic sortant ; avec 30 jours de rétention,
  prévoir 30 fois la taille de la bibliothèque plus la base. Le trafic entrant
  (envoi des sauvegardes) n'est pas facturé.
- Chiffrement au repos assuré par OVH ; pour un chiffrement supplémentaire côté VPS,
  ajouter un remote rclone de type `crypt` par-dessus `proxyphar-backup` et garder la
  phrase secrète au coffre, sinon les sauvegardes deviennent illisibles.
