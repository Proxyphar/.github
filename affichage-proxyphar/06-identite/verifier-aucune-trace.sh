#!/usr/bin/env bash
# Étape 6c — Contrôle explicite : aucune trace de « bubu.re » (ni « bubu ») nulle part.
#
# Recherche dans : la base du CMS (export complet), les réglages, les fichiers du thème,
# les fichiers de /opt/affichage, la configuration Nginx et système, les noms d'images Docker.
#
# Usage : sudo ./verifier-aucune-trace.sh [--motif MOTIF]   (motif par défaut : bubu)

KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/common.sh
. "$KIT_DIR/lib/common.sh"
MOTIF="bubu"
while [ $# -gt 0 ]; do
  case "$1" in
    --motif) MOTIF="$2"; shift 2 ;;
    --aide|-h|--help) sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) fatal "Option inconnue : $1" ;;
  esac
done
exiger_root
charger_config_env
TROUVE=0

palier "6c — Recherche de « $MOTIF » (insensible à la casse)"

# 1. Base de données : export complet en flux, sans écriture sur disque.
NB=$(compose exec -T -e MYSQL_PWD="$MYSQL_PASSWORD" cms-db mysqldump --single-transaction --no-tablespaces -u cms cms | grep -ci "$MOTIF" || true)
if [ "$NB" = "0" ]; then ok "Base de données : 0 occurrence"; else erreur "Base de données : $NB ligne(s) contenant « $MOTIF »"; TROUVE=$((TROUVE + NB)); fi

# 2. Réglages, utilisateurs, écrans, mises en page (lisible dans le compte rendu).
for requete in \
  "SELECT CONCAT('setting ', setting, '=', \`value\`) FROM setting WHERE \`value\` LIKE '%$MOTIF%'" \
  "SELECT CONCAT('user ', UserName, ' ', IFNULL(email,'')) FROM \`user\` WHERE UserName LIKE '%$MOTIF%' OR email LIKE '%$MOTIF%'" \
  "SELECT CONCAT('display ', display) FROM display WHERE display LIKE '%$MOTIF%'" \
  "SELECT CONCAT('layout ', layout) FROM layout WHERE layout LIKE '%$MOTIF%'" \
  "SELECT CONCAT('media ', name) FROM media WHERE name LIKE '%$MOTIF%' OR storedAs LIKE '%$MOTIF%'"; do
  RES=$(mysql_cms "$requete;" 2>/dev/null || true)
  [ -z "$RES" ] || { erreur "Occurrence : $RES"; TROUVE=$((TROUVE + 1)); }
done
ok "Réglages, utilisateurs, écrans, mises en page, médias : contrôlés"

# 3. Fichiers : thème, configuration, bibliothèque (fichiers texte uniquement), Nginx, système.
for chemin in "$AFFICHAGE_DIR/shared/cms/library/brand" "$AFFICHAGE_DIR/shared/cms/custom" "$AFFICHAGE_DIR/config.env" "$AFFICHAGE_DIR/docker-compose.yml" "$AFFICHAGE_DIR/DOCS" /etc/nginx /etc/hosts /etc/hostname /etc/letsencrypt/renewal /home /root /var/www; do
  [ -e "$chemin" ] || continue
  RES=$(grep -rIil "$MOTIF" "$chemin" 2>/dev/null || true)
  if [ -n "$RES" ]; then erreur "Fichier(s) contenant « $MOTIF » sous $chemin :"; printf '%s\n' "$RES" | sed 's/^/    /'; TROUVE=$((TROUVE + 1)); fi
done
RES=$(find "$AFFICHAGE_DIR" /etc/nginx /etc/letsencrypt -iname "*$MOTIF*" 2>/dev/null || true)
[ -z "$RES" ] || { erreur "Nom(s) de fichier contenant « $MOTIF » : $RES"; TROUVE=$((TROUVE + 1)); }
ok "Fichiers de thème, configuration, Nginx, certificats, /home, /root : contrôlés"

# 4. Docker : images, conteneurs, volumes, réseaux.
RES=$(docker images --format '{{.Repository}}:{{.Tag}}'; docker ps -a --format '{{.Names}}'; docker volume ls -q; docker network ls --format '{{.Name}}')
if printf '%s' "$RES" | grep -qi "$MOTIF"; then erreur "Objet Docker contenant « $MOTIF »"; TROUVE=$((TROUVE + 1)); else ok "Objets Docker : 0 occurrence"; fi

# 5. Identité annoncée par le CMS.
ABOUT=$(curl -s -H "Host: $AFFICHAGE_DOMAINE" http://127.0.0.1:8080/about/config)
if printf '%s' "$ABOUT" | grep -qi "$MOTIF"; then erreur "L'identité annoncée par le CMS contient « $MOTIF »"; TROUVE=$((TROUVE + 1)); else
  ok "Identité annoncée : $(printf '%s' "$ABOUT" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("appName"), "|", d.get("productName"), "| version", d.get("version"))' 2>/dev/null)"; fi

# 6. Certificat TLS.
if [ -f "/etc/letsencrypt/live/$AFFICHAGE_DOMAINE/cert.pem" ]; then
  if openssl x509 -in "/etc/letsencrypt/live/$AFFICHAGE_DOMAINE/cert.pem" -noout -text | grep -qi "$MOTIF"; then erreur "Le certificat mentionne « $MOTIF »"; TROUVE=$((TROUVE + 1)); else ok "Certificat TLS : 0 occurrence"; fi
fi

palier "6c — Résultat : $TROUVE occurrence(s) de « $MOTIF »"
[ "$TROUVE" -eq 0 ] && ok "Aucune trace. Étape suivante : 07-sauvegarde." || exit 2
