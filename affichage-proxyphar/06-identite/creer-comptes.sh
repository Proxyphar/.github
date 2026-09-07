#!/usr/bin/env bash
# Étape 6b — Comptes utilisateurs du CMS.
#
# - vérifie le compte administrateur créé à l'étape 4 ;
# - crée le groupe « Hotline PROXYPHAR » avec des fonctionnalités limitées à la gestion
#   des contenus et des écrans (aucune fonction d'administration système) ;
# - crée l'utilisateur « hotline » (type Utilisateur) membre de ce groupe, avec
#   changement de mot de passe obligatoire à la première connexion ;
# - partage le dossier racine (vue, modification, suppression) avec le groupe ;
# - vérifie la connexion des deux comptes.
#
# Les insertions reprennent exactement les colonnes utilisées par le code de Xibo 4.5.2
# (lib/Entity/User.php, lib/Entity/UserGroup.php, lib/Entity/Permission.php).
#
# Usage : sudo ./creer-comptes.sh

KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/common.sh
. "$KIT_DIR/lib/common.sh"
case "${1:-}" in --aide|-h|--help) sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;; esac
exiger_root
charger_config_env
lire() { grep -E "^# $1=" "$AFFICHAGE_DIR/config.env" | cut -d= -f2-; }
ADMIN_USER=$(lire AFFICHAGE_ADMIN_USER); ADMIN_PW=$(lire AFFICHAGE_ADMIN_PASSWORD)
HOTLINE_USER=$(lire AFFICHAGE_HOTLINE_USER); HOTLINE_PW=$(lire AFFICHAGE_HOTLINE_PASSWORD)
[ -n "$ADMIN_USER" ] && [ -n "$HOTLINE_USER" ] && [ -n "$HOTLINE_PW" ] || fatal "Comptes absents de config.env"
GROUPE='Hotline PROXYPHAR'

# Fonctionnalités accordées à la hotline (noms exacts de lib/Factory/UserGroupFactory.php 4.5.2).
FEATURES='["dashboard.status","dashboard.media.manager","dashboard.playlist","library.view","library.add","library.modify","layout.view","layout.add","layout.modify","layout.export","template.view","template.add","template.modify","playlist.view","playlist.add","playlist.modify","campaign.view","campaign.add","campaign.modify","schedule.view","schedule.agenda","schedule.add","schedule.modify","schedule.reminders","daypart.view","dataset.view","dataset.add","dataset.modify","dataset.data","tag.view","tag.tagging","folder.view","folder.add","folder.modify","displays.view","displays.add","displays.modify","displaygroup.view","displaygroup.add","displaygroup.modify","playersoftware.view","report.view","displays.reporting","notification.centre","drawer","user.profile","user.sharing"]'
# Exclues volontairement : users.*, usergroup.*, application.view, module.view, transition.view,
# task.view, log.view, session.view, auditlog.view, developer.*, command.*, display.sync*,
# displayprofile.*, resolution.*, font.*, menuBoard.*, ad.campaign, report.scheduling/saving.

palier "6b — Comptes du CMS"
attendre_cms http://127.0.0.1:8080/login 60 || fatal "Le CMS ne répond pas"

connexion() {
  # Vérifie une connexion via l'API de connexion (jeton anti-CSRF requis). Affiche la réponse JSON.
  local entetes cookies xsrf
  entetes=$(mktemp)
  curl -s -o /dev/null -D "$entetes" -H "Host: $AFFICHAGE_DOMAINE" -H "X-Forwarded-Proto: https" http://127.0.0.1:8080/login
  cookies=$(tr -d '\r' < "$entetes" | grep -i '^set-cookie:' | sed -E 's/^[Ss]et-[Cc]ookie: *([^;[:space:]]+).*/\1/' | paste -sd ';' -)
  xsrf=$(printf '%s' "$cookies" | tr ';' '\n' | sed -n 's/^XSRF-TOKEN=//p')
  rm -f "$entetes"
  curl -s -H "Host: $AFFICHAGE_DOMAINE" -H "X-Forwarded-Proto: https" -H "Cookie: $cookies" -H "X-XSRF-TOKEN: $xsrf" \
    --data-urlencode "username=$1" --data-urlencode "password=$2" http://127.0.0.1:8080/login
}

# --- Administrateur -------------------------------------------------------------------
NB=$(mysql_cms "SELECT COUNT(*) FROM \`user\` WHERE UserName='$ADMIN_USER' AND usertypeid=1;")
[ "$NB" = "1" ] || fatal "Administrateur $ADMIN_USER introuvable : relancer 04-cms/configurer-cms.sh"
REPONSE=$(connexion "$ADMIN_USER" "$ADMIN_PW")
[[ "$REPONSE" == *'"status":"ok"'* ]] && ok "Administrateur $ADMIN_USER : connexion vérifiée" || fatal "Connexion administrateur en échec : $REPONSE"

# --- Groupe hotline -------------------------------------------------------------------
GID=$(mysql_cms "SELECT groupId FROM \`group\` WHERE \`group\`='$GROUPE' AND IsUserSpecific=0 LIMIT 1;")
if [ -z "$GID" ]; then
  mysql_cms "INSERT INTO \`group\` (\`group\`, IsUserSpecific, description, libraryQuota, isSystemNotification, isDisplayNotification, isDataSetNotification, isLayoutNotification, isLibraryNotification, isReportNotification, isScheduleNotification, isCustomNotification, isShownForAddUser, defaultHomepageId) VALUES ('$GROUPE', 0, 'Gestion des contenus et des écrans, sans configuration système', 0, 0, 1, 0, 1, 1, 0, 1, 0, 1, 'icondashboard.view');"
  GID=$(mysql_cms "SELECT groupId FROM \`group\` WHERE \`group\`='$GROUPE' AND IsUserSpecific=0 LIMIT 1;")
  ok "Groupe « $GROUPE » créé (id $GID)"
else
  info "Groupe « $GROUPE » déjà présent (id $GID)"
fi
mysql_cms "UPDATE \`group\` SET features='$FEATURES' WHERE groupId=$GID;"
ok "Fonctionnalités du groupe appliquées ($(printf '%s' "$FEATURES" | tr ',' '\n' | wc -l) fonctions)"

# Partage du dossier racine (id 1) avec le groupe : vue, modification, suppression.
ENTITE=$(mysql_cms "SELECT entityId FROM permissionentity WHERE entity='Xibo\\\\Entity\\\\Folder' LIMIT 1;")
[ -n "$ENTITE" ] || fatal "Entité de permission Folder introuvable"
NB=$(mysql_cms "SELECT COUNT(*) FROM permission WHERE entityId=$ENTITE AND groupId=$GID AND objectId=1;")
if [ "$NB" = "0" ]; then
  mysql_cms "INSERT INTO permission (entityId, groupId, objectId, \`view\`, \`edit\`, \`delete\`) VALUES ($ENTITE, $GID, 1, 1, 1, 1);"
  ok "Dossier racine partagé avec le groupe (vue, modification, suppression)"
else
  mysql_cms "UPDATE permission SET \`view\`=1, \`edit\`=1, \`delete\`=1 WHERE entityId=$ENTITE AND groupId=$GID AND objectId=1;"
  info "Partage du dossier racine déjà présent (mis à jour)"
fi

# --- Utilisateur hotline ----------------------------------------------------------------
UID_H=$(mysql_cms "SELECT UserID FROM \`user\` WHERE UserName='$HOTLINE_USER' LIMIT 1;")
if [ -z "$UID_H" ]; then
  HASH=$(compose exec -T cms-web php -r 'echo password_hash($argv[1], PASSWORD_DEFAULT);' -- "$HOTLINE_PW")
  [ "${HASH#\$2y\$}" != "$HASH" ] || fatal "Empreinte de mot de passe inattendue"
  mysql_cms "INSERT INTO \`user\` (UserName, UserPassword, isPasswordChangeRequired, usertypeid, newUserWizard, email, homePageId, homeFolderId, CSPRNG, firstName, lastName, phone, ref1, ref2, ref3, ref4, ref5) VALUES ('$HOTLINE_USER', '$HASH', 1, 3, 0, NULL, 'icondashboard.view', 1, 2, 'Hotline', 'PROXYPHAR', NULL, NULL, NULL, NULL, NULL, NULL);"
  UID_H=$(mysql_cms "SELECT UserID FROM \`user\` WHERE UserName='$HOTLINE_USER' LIMIT 1;")
  # Groupe personnel de l'utilisateur (comme le fait Xibo à la création d'un compte).
  mysql_cms "INSERT INTO \`group\` (\`group\`, IsUserSpecific, description, libraryQuota, isSystemNotification, isDisplayNotification, isDataSetNotification, isLayoutNotification, isLibraryNotification, isReportNotification, isScheduleNotification, isCustomNotification, isShownForAddUser, defaultHomepageId) VALUES ('$HOTLINE_USER', 1, NULL, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, NULL);"
  GID_PERSO=$(mysql_cms "SELECT groupId FROM \`group\` WHERE \`group\`='$HOTLINE_USER' AND IsUserSpecific=1 LIMIT 1;")
  mysql_cms "INSERT INTO lkusergroup (groupId, userId) VALUES ($GID_PERSO, $UID_H) ON DUPLICATE KEY UPDATE groupId=groupId;"
  ok "Utilisateur $HOTLINE_USER créé (id $UID_H, type Utilisateur, changement de mot de passe à la première connexion)"
else
  info "Utilisateur $HOTLINE_USER déjà présent (id $UID_H)"
fi
mysql_cms "INSERT INTO lkusergroup (groupId, userId) VALUES ($GID, $UID_H) ON DUPLICATE KEY UPDATE groupId=groupId;"
ok "$HOTLINE_USER est membre de « $GROUPE »"

compose restart cms-memcached >/dev/null
REPONSE=$(connexion "$HOTLINE_USER" "$HOTLINE_PW")
if [[ "$REPONSE" == *'"status":"ok"'* ]]; then ok "Connexion hotline vérifiée : $REPONSE"; else erreur "Connexion hotline en échec : $REPONSE"; exit 2; fi

palier "6b — Résultat"
cat <<FIN
Comptes en place :
    $ADMIN_USER  (Super administrateur)
    $HOTLINE_USER  (Utilisateur, groupe « $GROUPE ») — mot de passe initial : $HOTLINE_PW
        à changer à la première connexion (obligatoire).
À faire dans l'interface, une fois connecté en administrateur :
    - renseigner une adresse e-mail sur chaque compte (rappels de mot de passe, 2FA) ;
    - activer l'authentification à deux facteurs sur le compte administrateur.
Étape suivante : 06-identite/verifier-aucune-trace.sh
FIN
