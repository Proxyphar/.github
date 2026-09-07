# Sauvegarde et restauration

## Ce qui est sauvegardé, où, combien de temps

| Élément | Contenu | Destination | Rétention |
|---------|---------|-------------|-----------|
| Export SQL (`cms.sql.gz`) | toute la base du CMS (réglages, utilisateurs, écrans, mises en page, planifications, statistiques) | `/opt/affichage/backups/<horodatage>/` et destination externe | 7 jours local, 30 jours externe |
| Archive `affichage-shared.tar.gz` | `/opt/affichage/shared` sans `shared/db` (médias, thème, `library/certs/` = clés du CMS, custom, userscripts) + `config.env` + `docker-compose.yml` + `DOCS` | destination externe uniquement, envoyée en flux | 30 jours |
| `manifeste.txt` | versions, compteurs, taille, empreinte de l'export | local et externe | idem |
| Export interne Xibo | `shared/backup/db/latest.sql.gz` (quotidien, produit par le conteneur) | local | 2 versions |
| Backup automatisé OVH Premium | image complète du VPS | infrastructure OVH | selon l'offre (vérifier dans le manager) |

Déclenchement : `affichage-backup.timer` chaque nuit à 03:15 (heure de Paris).
Journal : `/var/log/affichage-backup.log`. État : `/opt/affichage/backups/DERNIER-ETAT` (`OK ...`
ou `ECHEC ...`). Un e-mail est envoyé si `BACKUP_ALERT_EMAIL` est renseigné dans
`/opt/affichage/backup.env` et qu'un relais de courrier est configuré.

**Point critique** : `shared/cms/library/certs/` contient la clé privée et la clé de
chiffrement du CMS. Sans elles, une base restaurée ne peut plus lire certains secrets et
les players doivent être ré-enrôlés. Elles sont dans l'archive externe.

## Destination externe

Configurée avec `rclone config` (identifiants dans `/root/.config/rclone/rclone.conf`,
droits 600, jamais dans le dépôt). Recommandation : conteneur **Object Storage OVHcloud**
(S3, région GRA ou, mieux, une autre région) dédié, avec un utilisateur S3 limité à ce
conteneur. Chiffrement possible au niveau de rclone (remote de type `crypt`) : dans ce
cas, la phrase secrète rclone doit être conservée au coffre, sinon les sauvegardes sont
illisibles.

Vérifier manuellement :

```bash
sudo rclone lsf --dirs-only "$(sudo sed -n 's/^BACKUP_REMOTE=//p' /opt/affichage/backup.env)"
sudo tail -20 /var/log/affichage-backup.log
```

## Lancer une sauvegarde à la main

```bash
sudo /opt/affichage/bin/affichage-backup.sh
```

À faire avant toute mise à jour de Xibo ou intervention sur la base.

## Tester une restauration (mensuel)

```bash
sudo /opt/affichage/bin/affichage-restore.sh --sauvegarde derniere
sudo /opt/affichage/bin/affichage-restore.sh --nettoyer
```

Le test déploie une copie complète dans `/opt/affichage-restore-test` (port local 8081, pile
Docker `affichage-test`) et compare les compteurs au manifeste. Il double temporairement la
bibliothèque sur le disque et consomme ~1,5 Go de mémoire : à faire hors heures
d'exploitation, et sur une autre machine Docker si la bibliothèque dépasse 20 Go
(copier le dossier de sauvegarde et le fichier `config.env`, puis lancer le script avec
`--source local`).

## Restauration réelle

### Cas 1 : base corrompue, VPS intact

```bash
cd /opt/affichage && sudo docker compose down
sudo /opt/affichage/bin/affichage-restore.sh --sauvegarde <horodatage> --production
```

Le dossier `shared` précédent est renommé `shared.avant-restauration.<date>` et conservé
jusqu'à validation. Vérifier l'accès, les écrans, puis le supprimer.

### Cas 2 : VPS perdu

1. Réinstaller le VPS et dérouler les étapes 0 à 5 du kit (`/opt/affichage-kit`), avec
   l'option `--forcer` à l'étape 4 si un `config.env` a été restauré au préalable.
   Sinon, l'étape 4 crée un `config.env` neuf : le `MYSQL_PASSWORD` sera **remplacé** par
   celui de la sauvegarde lors de la restauration (le fichier est dans l'archive).
2. `rclone config` pour recréer le remote, puis :

```bash
sudo /opt/affichage/bin/affichage-restore.sh --sauvegarde derniere --production
```

3. Relancer `06-identite/verifier-aucune-trace.sh` et `08-recette/recette.sh`.

### Cas 3 : restauration d'image OVH

Le Backup automatisé OVH restaure le VPS entier à une date donnée (manager > VPS >
Sauvegarde automatisée > Restaurer). Il remplace tout le disque : à réserver aux
sinistres complets, et à compléter par une restauration de la dernière sauvegarde
externe si elle est plus récente.

## Rotation et espace

- Externe : `rclone delete --min-age 30d` puis suppression des dossiers vides, à chaque
  sauvegarde.
- Local : dossiers `/opt/affichage/backups/*` de plus de 7 jours supprimés à chaque sauvegarde.
- Surveiller la taille de la destination : ≈ 30 × (base + bibliothèque). Avec une
  bibliothèque de 20 Go, prévoir 600 Go sur la destination, ou réduire
  `BACKUP_KEEP_DAYS`.
