#!/usr/bin/env bash
# Sauvegarde quotidienne du CMS PROXYPHAR Affichage — installé dans /opt/affichage/bin/affichage-backup.sh
#
# 1. Export SQL cohérent (mysqldump --single-transaction) -> /opt/affichage/backups/AAAA-MM-JJ_HHMM/cms.sql.gz
# 2. Archive de /opt/affichage/shared (sans shared/db, restaurée depuis l'export SQL, et sans
#    les fichiers temporaires) + config.env + docker-compose.yml, transmise EN FLUX à la
#    destination externe (aucune copie locale de la bibliothèque : disque de 80 Go).
# 3. Manifeste (versions, comptes d'objets, tailles, empreintes) pour le test de restauration.
# 4. Rotation : 30 jours sur la destination, 7 jours pour les exports SQL locaux.
#
# Usage : affichage-backup.sh [--sans-externe]   (--sans-externe : export SQL local seulement)

set -o errexit; set -o nounset; set -o pipefail
AFFICHAGE_DIR="${AFFICHAGE_DIR:-/opt/affichage}"
LOG=/var/log/affichage-backup.log
VERROU=/run/lock/affichage-backup.lock
SANS_EXTERNE=0
[ "${1:-}" = "--sans-externe" ] && SANS_EXTERNE=1

journal() { printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" | tee -a "$LOG"; }
echec() {
  journal "ECHEC : $*"
  printf 'ECHEC %s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" > "$AFFICHAGE_DIR/backups/DERNIER-ETAT"
  if [ -n "${BACKUP_ALERT_EMAIL:-}" ] && command -v mail >/dev/null 2>&1; then
    printf 'La sauvegarde PROXYPHAR Affichage du %s a échoué : %s\nVoir %s sur le VPS.\n' "$(date '+%d/%m/%Y %H:%M')" "$*" "$LOG" \
      | mail -s "[PROXYPHAR Affichage] ECHEC sauvegarde" "$BACKUP_ALERT_EMAIL" || true
  fi
  exit 1
}

exec 9>"$VERROU"
flock -n 9 || { journal "Une sauvegarde est déjà en cours, abandon."; exit 0; }
[ "$(id -u)" -eq 0 ] || echec "à lancer en root"
[ -f "$AFFICHAGE_DIR/config.env" ] || echec "config.env introuvable"
set -o allexport
# shellcheck disable=SC1091
. "$AFFICHAGE_DIR/config.env"
[ -f "$AFFICHAGE_DIR/backup.env" ] && . "$AFFICHAGE_DIR/backup.env"
set +o allexport
BACKUP_KEEP_DAYS="${BACKUP_KEEP_DAYS:-30}"
BACKUP_LOCAL_KEEP_DAYS="${BACKUP_LOCAL_KEEP_DAYS:-7}"

HORODATAGE=$(date '+%Y-%m-%d_%H%M')
LOCAL="$AFFICHAGE_DIR/backups/$HORODATAGE"
mkdir -p "$LOCAL"
journal "Début de la sauvegarde $HORODATAGE"

# --- 1. Export SQL --------------------------------------------------------------------
( cd "$AFFICHAGE_DIR" && docker compose exec -T -e MYSQL_PWD="$MYSQL_PASSWORD" cms-db \
    mysqldump --single-transaction --hex-blob --no-tablespaces --routines --triggers -u cms cms ) \
  | gzip -6 > "$LOCAL/cms.sql.gz" || echec "export SQL"
[ "$(stat -c %s "$LOCAL/cms.sql.gz")" -gt 10240 ] || echec "export SQL anormalement petit"
journal "Export SQL : $(du -h "$LOCAL/cms.sql.gz" | cut -f1)"

# --- 2. Manifeste ---------------------------------------------------------------------
sql() { ( cd "$AFFICHAGE_DIR" && docker compose exec -T -e MYSQL_PWD="$MYSQL_PASSWORD" cms-db mysql --batch --skip-column-names -u cms cms -e "$1" ); }
cat > "$LOCAL/manifeste.txt" <<FIN
horodatage=$HORODATAGE
hote=$(hostname)
version_cms=$(curl -s -m 10 -H 'Host: intranet.proxyphar.fr' http://127.0.0.1:8080/about/config | sed -n 's/.*"version":"\([^"]*\)".*/\1/p')
images=$( (cd "$AFFICHAGE_DIR" && docker compose config --images) | tr '\n' ' ')
nb_media=$(sql "SELECT COUNT(*) FROM media;")
nb_layout=$(sql "SELECT COUNT(*) FROM layout;")
nb_display=$(sql "SELECT COUNT(*) FROM display;")
nb_user=$(sql "SELECT COUNT(*) FROM \`user\`;")
taille_library=$(du -sb "$AFFICHAGE_DIR/shared/cms/library" | cut -f1)
sha256_sql=$(sha256sum "$LOCAL/cms.sql.gz" | cut -d' ' -f1)
FIN
journal "Manifeste : $(grep -E '^nb_' "$LOCAL/manifeste.txt" | tr '\n' ' ')"

# --- 3. Archive en flux vers la destination externe ---------------------------------------
if [ "$SANS_EXTERNE" -eq 1 ]; then
  journal "Mode --sans-externe : pas d'envoi vers la destination externe"
else
  [ -n "${BACKUP_REMOTE:-}" ] || echec "BACKUP_REMOTE non défini dans $AFFICHAGE_DIR/backup.env"
  command -v rclone >/dev/null 2>&1 || echec "rclone absent"
  DEST="$BACKUP_REMOTE/$HORODATAGE"
  rclone copy "$LOCAL/cms.sql.gz" "$DEST/" || echec "envoi de l'export SQL"
  rclone copy "$LOCAL/manifeste.txt" "$DEST/" || echec "envoi du manifeste"
  ( cd "$AFFICHAGE_DIR" && tar --create --gzip --warning=no-file-changed \
      --exclude='./shared/db' --exclude='./shared/cms/library/temp' --exclude='./shared/cms/library/cache' \
      --exclude='./shared/backup' \
      ./shared ./config.env ./docker-compose.yml ./backup.env ./DOCS 2>/dev/null || [ $? -eq 1 ] ) \
    | rclone rcat "$DEST/affichage-shared.tar.gz" || echec "envoi de l'archive shared"
  TAILLE=$(rclone size --json "$DEST" | python3 -c 'import json,sys; print(json.load(sys.stdin)["bytes"])')
  [ "$TAILLE" -gt 20480 ] || echec "archive externe anormalement petite ($TAILLE octets)"
  journal "Archive envoyée vers $DEST ($(numfmt --to=iec "$TAILLE"))"
  # Rotation externe : suppression des sauvegardes plus anciennes que BACKUP_KEEP_DAYS.
  rclone delete --min-age "${BACKUP_KEEP_DAYS}d" "$BACKUP_REMOTE" || journal "Avertissement : rotation externe incomplète"
  rclone rmdirs --leave-root "$BACKUP_REMOTE" || true
fi

# --- 4. Rotation locale --------------------------------------------------------------------
find "$AFFICHAGE_DIR/backups" -mindepth 1 -maxdepth 1 -type d -mtime +"$BACKUP_LOCAL_KEEP_DAYS" -exec rm -rf {} +
printf 'OK %s %s\n' "$HORODATAGE" "${DEST:-local}" > "$AFFICHAGE_DIR/backups/DERNIER-ETAT"
journal "Sauvegarde $HORODATAGE terminée avec succès"
