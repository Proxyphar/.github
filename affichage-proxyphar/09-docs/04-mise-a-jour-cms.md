# Mettre à jour Xibo CMS

Xibo publie des correctifs de la branche 4.x environ tous les mois (versions
`4.5.x`) et des versions mineures (`4.6`, ...) quelques fois par an. Les correctifs de
sécurité sont annoncés sur https://xibosignage.com/blog et sur le dépôt
https://github.com/xibosignage/xibo-cms/releases.

## Règles

1. Rester sur la **dernière version stable 4.x** ; ne pas installer de version
   `-alpha`, `-beta`, `-rc`.
2. Lire les notes de version : elles signalent les changements demandant une action
   (nouvelle image MySQL, réglages, players minimum).
3. Toujours mettre à jour à partir du fichier `docker-compose.yml` officiel de la version
   cible (dépôt `xibosignage/xibo-docker`, tag de la version) pour repérer une nouvelle
   image ou variable ; reporter ensuite les changements dans `/opt/affichage/docker-compose.yml`
   en conservant nos adaptations (ports sur 127.0.0.1, aucun port sur la base et XMR,
   sous-réseau 172.28.0.0/24, tags figés).
4. Mettre à jour les players ensuite, pour rester sur la même version majeure.

## Procédure (fenêtre de 30 minutes, hors heures d'exploitation)

```bash
sudo -i
cd /opt/affichage

# 1. Sauvegarde préalable
/opt/affichage/bin/affichage-backup.sh

# 2. Nouvelle version : tags à figer (exemple 4.5.3)
cp docker-compose.yml DOCS/docker-compose.yml.avant-4.5.3
sed -i 's/xibo-cms:release-4.5.2/xibo-cms:release-4.5.3/' docker-compose.yml
# si les notes de version demandent une autre image XMR ou MySQL, la modifier de même

# 3. Téléchargement et remplacement des conteneurs
docker compose pull
docker compose up -d
docker compose logs -f cms-web      # attendre « Starting webserver » ; Ctrl-C pour quitter
```

Au démarrage, l'entrypoint du conteneur détecte la nouvelle version, réalise un export
SQL dans `shared/backup/` et applique les migrations de base. Le CMS est indisponible
quelques minutes ; les players continuent d'afficher leur contenu local.

## Vérifications après mise à jour

```bash
curl -s https://intranet.proxyphar.fr/about/config | python3 -m json.tool | grep -E 'version|appName'
docker compose ps
/opt/affichage-kit/06-identite/verifier-aucune-trace.sh
```

Puis, dans le navigateur : connexion administrateur, page **Écrans** (états verts),
lecture d'une mise en page en aperçu. Consigner la version et la date dans
`DOCS/empreintes-images.txt` :

```bash
for i in $(docker compose config --images); do printf '%s %s\n' "$i" "$(docker image inspect --format '{{index .RepoDigests 0}}' "$i")"; done >> DOCS/empreintes-images.txt
docker image prune -f      # libère l'espace des anciennes images
```

## Retour arrière

Si la nouvelle version pose problème dans l'heure :

```bash
cd /opt/affichage && docker compose down
cp DOCS/docker-compose.yml.avant-4.5.3 docker-compose.yml
/opt/affichage/bin/affichage-restore.sh --sauvegarde derniere --production   # base d'avant migration
```

Une base migrée vers une version plus récente **ne peut pas** être relue par l'ancienne
version : la restauration de l'export préalable est indispensable au retour arrière.

## Système et Nginx

- Mises à jour de sécurité Ubuntu : automatiques (`unattended-upgrades`), sans
  redémarrage automatique. Vérifier `/var/run/reboot-required` chaque mois et redémarrer
  dans la fenêtre de maintenance (`sudo reboot` ; tout remonte seul, voir la recette).
- Docker Engine : `sudo apt-get update && sudo apt-get upgrade` dans la même fenêtre.
- Certificat : renouvelé automatiquement (`certbot.timer`) ; contrôle mensuel avec
  `sudo certbot certificates`.
