#!/usr/bin/env bash
# Restauration du CMS PROXYPHAR Affichage — installé dans /opt/affichage/bin/affichage-restore.sh
#
# Restaure une sauvegarde (export SQL + archive shared) dans un dossier cible, sur une
# pile Docker séparée. Sert au TEST DE RESTAURATION SUR COPIE et à la restauration réelle.
#
# Usage :
#   affichage-restore.sh --sauvegarde HORODATAGE|derniere [--cible /opt/affichage-restore-test] [--port 8081]
#                   [--source rclone|local] [--production]
#   --sauvegarde   nom du dossier de sauvegarde (AAAA-MM-JJ_HHMM) ou « derniere »
#   --cible        dossier de restauration (défaut : /opt/affichage-restore-test, pile « affichage-test »)
#   --port         port local de la copie (défaut : 8081)
#   --source       rclone (destination externe, défaut) ou local (export SQL local + shared en place)
#   --production   restaure DANS /opt/affichage à la place de la pile de production (destructif,
#                  confirmation demandée ; arrêter la production avant)
#
# Après un test, supprimer la copie :  affichage-restore.sh --nettoyer [--cible ...]

set -o errexit; set -o nounset; set -o pipefail
AFFICHAGE_DIR="${AFFICHAGE_DIR:-/opt/affichage}"
SAUVEGARDE=""; CIBLE=/opt/affichage-restore-test; PORT=8081; SOURCE=rclone; PRODUCTION=0; NETTOYER=0
while [ $# -gt 0 ]; do
  case "$1" in
    --sauvegarde) SAUVEGARDE="$2"; shift 2 ;;
    --cible) CIBLE="$2"; shift 2 ;;
    --port) PORT="$2"; shift 2 ;;
    --source) SOURCE="$2"; shift 2 ;;
    --production) PRODUCTION=1; shift ;;
    --nettoyer) NETTOYER=1; shift ;;
    --aide|-h|--help) sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Option inconnue : $1" >&2; exit 1 ;;
  esac
done
[ "$(id -u)" -eq 0 ] || { echo "À lancer en root" >&2; exit 1; }
journal() { printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"; }

if [ "$PRODUCTION" -eq 1 ]; then CIBLE="$AFFICHAGE_DIR"; PROJET=affichage; PORT=8080; else PROJET=affichage-test; fi
dc() { ( cd "$CIBLE" && docker compose -p "$PROJET" "$@" ); }

if [ "$NETTOYER" -eq 1 ]; then
  [ "$CIBLE" != "$AFFICHAGE_DIR" ] || { echo "Refus de nettoyer la production" >&2; exit 1; }
  [ -d "$CIBLE" ] && dc down -v --remove-orphans >/dev/null 2>&1 || true
  rm -rf "$CIBLE"
  journal "Copie $CIBLE supprimée"
  exit 0
fi
[ -n "$SAUVEGARDE" ] || { echo "Indiquer --sauvegarde HORODATAGE|derniere" >&2; exit 1; }

set -o allexport
# shellcheck disable=SC1091
. "$AFFICHAGE_DIR/config.env"
[ -f "$AFFICHAGE_DIR/backup.env" ] && . "$AFFICHAGE_DIR/backup.env"
set +o allexport

# --- Récupération de la sauvegarde ------------------------------------------------------
TRAVAIL=$(mktemp -d /var/tmp/affichage-restore.XXXXXX)
trap 'rm -rf "$TRAVAIL"' EXIT
if [ "$SOURCE" = "rclone" ]; then
  [ -n "${BACKUP_REMOTE:-}" ] || { echo "BACKUP_REMOTE non défini" >&2; exit 1; }
  if [ "$SAUVEGARDE" = "derniere" ]; then
    SAUVEGARDE=$(rclone lsf --dirs-only "$BACKUP_REMOTE" | sed 's#/$##' | sort | tail -1)
  fi
  journal "Téléchargement de $BACKUP_REMOTE/$SAUVEGARDE"
  rclone copy "$BACKUP_REMOTE/$SAUVEGARDE" "$TRAVAIL/" || { echo "Téléchargement en échec" >&2; exit 1; }
else
  if [ "$SAUVEGARDE" = "derniere" ]; then
    SAUVEGARDE=$(find "$AFFICHAGE_DIR/backups" -mindepth 1 -maxdepth 1 -type d -name '[0-9][0-9][0-9][0-9]-*' -printf '%f\n' | sort | tail -1)
  fi
  cp "$AFFICHAGE_DIR/backups/$SAUVEGARDE"/cms.sql.gz "$AFFICHAGE_DIR/backups/$SAUVEGARDE"/manifeste.txt "$TRAVAIL/"
fi
[ -f "$TRAVAIL/cms.sql.gz" ] || { echo "cms.sql.gz absent de la sauvegarde $SAUVEGARDE" >&2; exit 1; }
SHA_ATTENDU=$(sed -n 's/^sha256_sql=//p' "$TRAVAIL/manifeste.txt")
SHA_REEL=$(sha256sum "$TRAVAIL/cms.sql.gz" | cut -d' ' -f1)
[ "$SHA_ATTENDU" = "$SHA_REEL" ] || { echo "Empreinte de l'export SQL différente du manifeste : sauvegarde corrompue" >&2; exit 1; }
journal "Sauvegarde $SAUVEGARDE vérifiée (empreinte SQL conforme)"

# --- Préparation de la cible -------------------------------------------------------------
if [ "$PRODUCTION" -eq 1 ]; then
  printf 'RESTAURATION EN PRODUCTION : %s va être remplacé par la sauvegarde %s. Tapez « oui » pour continuer : ' "$AFFICHAGE_DIR" "$SAUVEGARDE"
  read -r rep; [ "$rep" = "oui" ] || exit 0
  dc down >/dev/null 2>&1 || true
  HORO=$(date '+%Y%m%d_%H%M%S')
  mv "$AFFICHAGE_DIR/shared" "$AFFICHAGE_DIR/shared.avant-restauration.$HORO"
  journal "Ancien dossier shared conservé : $AFFICHAGE_DIR/shared.avant-restauration.$HORO (à supprimer après validation)"
else
  [ ! -d "$CIBLE" ] || { echo "$CIBLE existe déjà : lancer d'abord --nettoyer" >&2; exit 1; }
  mkdir -p "$CIBLE"
fi
mkdir -p "$CIBLE/shared/db" "$CIBLE/shared/backup" "$CIBLE/shared/cms"/{custom,library,web/userscripts,ca-certs}

if [ "$SOURCE" = "rclone" ]; then
  journal "Extraction de l'archive shared"
  tar --extract --gzip --file "$TRAVAIL/affichage-shared.tar.gz" --directory "$CIBLE" --exclude='./shared/db'
else
  journal "Copie de la bibliothèque depuis la production (source locale)"
  rsync -a --exclude='temp/' --exclude='cache/' "$AFFICHAGE_DIR/shared/cms/" "$CIBLE/shared/cms/"
  cp "$AFFICHAGE_DIR/config.env" "$AFFICHAGE_DIR/docker-compose.yml" "$CIBLE/"
fi
[ -f "$CIBLE/config.env" ] || cp "$AFFICHAGE_DIR/config.env" "$CIBLE/config.env"
[ -f "$CIBLE/docker-compose.yml" ] || cp "$AFFICHAGE_DIR/docker-compose.yml" "$CIBLE/docker-compose.yml"
chmod 600 "$CIBLE/config.env"
rm -rf "$CIBLE/shared/db"/* "$CIBLE/shared/cms/library/cache" "$CIBLE/shared/cms/library/temp"
# L'entrypoint du conteneur importe /var/www/backup/import.sql au démarrage, puis applique
# les migrations si l'export provient d'une version plus ancienne.
gunzip -c "$TRAVAIL/cms.sql.gz" > "$CIBLE/shared/backup/import.sql"

if [ "$PRODUCTION" -eq 0 ]; then
  # Copie de test : autre nom de projet, autre port local, autre sous-réseau, mémoire réduite.
  sed -i -e 's/^name: affichage$/name: affichage-test/' -e "s/127.0.0.1:8080:80/127.0.0.1:$PORT:80/" \
         -e 's/name: affichage_default/name: affichage_test_default/' -e 's#172.28.0.0/24#172.29.0.0/24#' -e 's/172.28.0.1/172.29.0.1/' \
         -e 's/mem_limit: 1g/mem_limit: 768m/' "$CIBLE/docker-compose.yml"
  sed -i "s#172.28.0.0/24#172.29.0.0/24#" "$CIBLE/shared/cms/custom/settings-custom.php" 2>/dev/null || true
fi

journal "Démarrage de la pile $PROJET dans $CIBLE"
dc up -d
for i in $(seq 1 240); do
  CODE=$(curl -s -o /dev/null -w '%{http_code}' -H "Host: intranet.proxyphar.fr" "http://127.0.0.1:$PORT/login" || true)
  case "$CODE" in 200|302) break ;; esac
  sleep 3
  [ "$i" -lt 240 ] || { echo "Le CMS restauré ne répond pas ; journaux :" >&2; dc logs --tail=40 cms-web; exit 1; }
done
[ ! -f "$CIBLE/shared/backup/import.sql" ] || { echo "import.sql non consommé par l'entrypoint (import non réalisé)" >&2; exit 1; }
sql() { dc exec -T -e MYSQL_PWD="$MYSQL_PASSWORD" cms-db mysql --batch --skip-column-names -u cms cms -e "$1"; }
ECARTS=0
for cle in nb_media nb_layout nb_display nb_user; do
  attendu=$(sed -n "s/^$cle=//p" "$TRAVAIL/manifeste.txt")
  table=${cle#nb_}; [ "$table" = "user" ] && table='`user`'
  reel=$(sql "SELECT COUNT(*) FROM $table;")
  if [ "$attendu" = "$reel" ]; then journal "$cle : $reel (conforme)"; else journal "$cle : $reel, attendu $attendu"; ECARTS=$((ECARTS + 1)); fi
done
NB_FICHIERS=$(find "$CIBLE/shared/cms/library" -type f | wc -l)
journal "Fichiers de bibliothèque restaurés : $NB_FICHIERS"
[ -f "$CIBLE/shared/cms/library/certs/private.key" ] && journal "Clés du CMS (certs/) présentes" || { journal "Clés du CMS ABSENTES"; ECARTS=$((ECARTS + 1)); }
CLE_CMS=$(sql "SELECT \`value\` FROM setting WHERE setting='SERVER_KEY';")
journal "Clé CMS restaurée : $CLE_CMS"
if [ "$ECARTS" -eq 0 ]; then
  journal "RESTAURATION VALIDÉE (sauvegarde $SAUVEGARDE, pile $PROJET, http://127.0.0.1:$PORT)"
  [ "$PRODUCTION" -eq 0 ] && journal "Supprimer la copie après contrôle : $0 --nettoyer --cible $CIBLE"
else
  journal "RESTAURATION AVEC $ECARTS ÉCART(S) : ne pas valider"; exit 2
fi
