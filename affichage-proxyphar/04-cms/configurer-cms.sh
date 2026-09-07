#!/usr/bin/env bash
# Étape 4 (suite) — Configuration du CMS Xibo pour PROXYPHAR.
# Appelé par installer-cms.sh ; peut être relancé seul (idempotent).
#
# Applique dans la base du CMS, comme le fait l'entrypoint officiel de l'image :
#   - langue « fr », fuseau Europe/Paris, format de date français ;
#   - adresse XMR WebSocket publique, adresse ZeroMQ désactivée ;
#   - limite de bibliothèque 40 Go ; clé CMS ; position par défaut ; 2FA « PROXYPHAR » ;
#   - renommage de xibo_admin en admin_proxyphar avec le mot de passe de config.env.
# Puis redémarre le cache et le conteneur web, et vérifie la connexion administrateur.
#
# Usage : sudo ./configurer-cms.sh

KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/common.sh
. "$KIT_DIR/lib/common.sh"
case "${1:-}" in --aide|-h|--help) sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;; esac
exiger_root
charger_config_env

ADMIN_USER=$(grep -E '^# AFFICHAGE_ADMIN_USER=' "$AFFICHAGE_DIR/config.env" | cut -d= -f2-)
ADMIN_PW=$(grep -E '^# AFFICHAGE_ADMIN_PASSWORD=' "$AFFICHAGE_DIR/config.env" | cut -d= -f2-)
CMS_KEY=$(grep -E '^# AFFICHAGE_CMS_KEY=' "$AFFICHAGE_DIR/config.env" | cut -d= -f2-)
[ -n "$ADMIN_USER" ] && [ -n "$ADMIN_PW" ] && [ -n "$CMS_KEY" ] || fatal "Comptes absents de config.env (lignes # AFFICHAGE_...)"

palier "4b — Paramétrage du CMS"
attendre_cms http://127.0.0.1:8080/login 120 || fatal "Le CMS ne répond pas"

# Limite de bibliothèque : 40 Go sur un disque de 80 Go (voir DOCS/01-architecture-et-versions.md).
LIB_LIMITE_KB=$((40 * 1024 * 1024))

# Réglages (table setting). Les lignes existent déjà : un UPDATE suffit et reste sans effet
# si le paramètre était absent ; on vérifie ensuite les valeurs effectives.
mysql_cms <<SQL
UPDATE \`setting\` SET \`value\`='fr' WHERE \`setting\`='DEFAULT_LANGUAGE';
UPDATE \`setting\` SET \`value\`='0' WHERE \`setting\`='DETECT_LANGUAGE';
UPDATE \`setting\` SET \`value\`='Europe/Paris' WHERE \`setting\`='defaultTimezone';
UPDATE \`setting\` SET \`value\`='d/m/Y H:i' WHERE \`setting\`='DATE_FORMAT';
UPDATE \`setting\` SET \`value\`='$LIB_LIMITE_KB' WHERE \`setting\`='LIBRARY_SIZE_LIMIT_KB';
UPDATE \`setting\` SET \`value\`='wss://$AFFICHAGE_DOMAINE/xmr' WHERE \`setting\`='XMR_WS_ADDRESS';
UPDATE \`setting\` SET \`value\`='' WHERE \`setting\`='XMR_PUB_ADDRESS';
UPDATE \`setting\` SET \`value\`='$CMS_KEY' WHERE \`setting\`='SERVER_KEY';
UPDATE \`setting\` SET \`value\`='50.6233' WHERE \`setting\`='DEFAULT_LAT';
UPDATE \`setting\` SET \`value\`='3.1457' WHERE \`setting\`='DEFAULT_LONG';
UPDATE \`setting\` SET \`value\`='PROXYPHAR Affichage' WHERE \`setting\`='TWOFACTOR_ISSUER';
UPDATE \`setting\` SET \`value\`='0' WHERE \`setting\`='DISPLAY_AUTO_AUTH';
UPDATE \`setting\` SET \`value\`='0' WHERE \`setting\`='FORCE_HTTPS';
UPDATE \`setting\` SET \`value\`='0' WHERE \`setting\`='ISSUE_STS';
UPDATE \`setting\` SET \`value\`='0' WHERE \`setting\`='PHONE_HOME';
SQL
ok "Réglages appliqués"

# Compte administrateur : renommage de l'utilisateur 1 et empreinte bcrypt calculée par le PHP du CMS.
HASH=$(compose exec -T cms-web php -r 'echo password_hash($argv[1], PASSWORD_DEFAULT);' -- "$ADMIN_PW")
[ "${HASH#\$2y\$}" != "$HASH" ] || fatal "Empreinte de mot de passe inattendue"
mysql_cms "UPDATE \`user\` SET UserName='$ADMIN_USER', UserPassword='$HASH', CSPRNG=2, isPasswordChangeRequired=0, newUserWizard=0 WHERE UserID=1 LIMIT 1;"
ok "Administrateur : $ADMIN_USER (mot de passe défini, empreinte bcrypt)"

# Le CMS met les réglages en cache : redémarrage du cache et du conteneur web.
compose restart cms-memcached cms-web >/dev/null
attendre_cms http://127.0.0.1:8080/login 120 || fatal "Le CMS ne répond plus après redémarrage"

info "Valeurs effectives :"
mysql_cms "SELECT CONCAT('    ', setting, ' = ', IFNULL(\`value\`,'')) FROM \`setting\` WHERE setting IN ('DEFAULT_LANGUAGE','defaultTimezone','DATE_FORMAT','LIBRARY_SIZE_LIMIT_KB','XMR_WS_ADDRESS','XMR_PUB_ADDRESS','DISPLAY_AUTO_AUTH','PHONE_HOME','SENDFILE_MODE','LIBRARY_LOCATION') ORDER BY setting;"

# Vérification de connexion via l'API de connexion du CMS (jeton anti-CSRF requis).
ENTETES=$(mktemp)
curl -s -o /dev/null -D "$ENTETES" -H "Host: $AFFICHAGE_DOMAINE" -H "X-Forwarded-Proto: https" http://127.0.0.1:8080/login
COOKIES=$(tr -d '\r' < "$ENTETES" | grep -i '^set-cookie:' | sed -E 's/^[Ss]et-[Cc]ookie: *([^;[:space:]]+).*/\1/' | paste -sd ';' -)
XSRF=$(printf '%s' "$COOKIES" | tr ';' '\n' | sed -n 's/^XSRF-TOKEN=//p')
REPONSE=$(curl -s -H "Host: $AFFICHAGE_DOMAINE" -H "X-Forwarded-Proto: https" -H "Cookie: $COOKIES" -H "X-XSRF-TOKEN: $XSRF" \
  --data-urlencode "username=$ADMIN_USER" --data-urlencode "password=$ADMIN_PW" http://127.0.0.1:8080/login)
rm -f "$ENTETES"
if [[ "$REPONSE" == *'"status":"ok"'* ]]; then
  ok "Connexion administrateur vérifiée ($ADMIN_USER)"
else
  erreur "Échec de la connexion administrateur. Réponse du CMS : $REPONSE"
  exit 2
fi
