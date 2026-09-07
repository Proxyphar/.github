#!/usr/bin/env bash
# Étape 8 — Contrôles automatiques de recette (voir checklist-recette.md).
#
# Usage : sudo ./recette.sh [--apres-redemarrage]
#   --apres-redemarrage : contrôle 12 uniquement (services remontés seuls après reboot)

KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/common.sh
. "$KIT_DIR/lib/common.sh"
APRES=0
case "${1:-}" in
  --apres-redemarrage) APRES=1 ;;
  --aide|-h|--help) sed -n '2,6p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  "") ;;
  *) fatal "Option inconnue : $1" ;;
esac
exiger_root
charger_config_env
ECARTS=0
verif() { if eval "$2"; then ok "$1"; else erreur "$1"; ECARTS=$((ECARTS + 1)); fi; }

if [ "$APRES" -eq 1 ]; then
  palier "8 — Contrôle 12 : services après redémarrage (démarré depuis $(uptime -p))"
  verif "Démarrage récent (moins de 30 min)" "[ \$(awk '{print int(\$1)}' /proc/uptime) -lt 1800 ]"
  verif "Docker actif" "systemctl is-active --quiet docker"
  verif "Nginx actif" "systemctl is-active --quiet nginx"
  verif "UFW actif" "ufw status | grep -q 'Status: active'"
  verif "fail2ban actif" "systemctl is-active --quiet fail2ban"
  verif "5 conteneurs Xibo en cours d'exécution" "[ \$(compose ps --status running -q | wc -l) -eq 5 ]"
  verif "CMS joignable en HTTPS (200)" "[ \$(curl -s -o /dev/null -w '%{http_code}' https://$AFFICHAGE_DOMAINE/login) = 200 ]"
  verif "Minuterie de sauvegarde active" "systemctl is-active --quiet affichage-backup.timer"
  verif "Minuterie certbot active" "systemctl is-active --quiet certbot.timer"
  palier "8 — Résultat après redémarrage : $ECARTS écart(s)"
  [ "$ECARTS" -eq 0 ] || exit 2
  exit 0
fi

palier "8 — Contrôles automatiques de recette"
info "Contrôle 1 et 3 : frontal HTTPS"
"$KIT_DIR/05-nginx-tls/verifier-tls.sh" || ECARTS=$((ECARTS + 1))

info "Contrôle 7 : aucune trace"
"$KIT_DIR/06-identite/verifier-aucune-trace.sh" || ECARTS=$((ECARTS + 1))

palier "8 — Contrôles 13, 16, 18"
verif "Dernière sauvegarde en état OK" "grep -q '^OK ' $AFFICHAGE_DIR/backups/DERNIER-ETAT"
if [ -f "$AFFICHAGE_DIR/backup.env" ]; then
  REMOTE=$(sed -n 's/^BACKUP_REMOTE=//p' "$AFFICHAGE_DIR/backup.env")
  verif "Sauvegarde présente sur la destination externe ($REMOTE)" "[ -n '$REMOTE' ] && [ \$(rclone lsf --dirs-only '$REMOTE' | wc -l) -ge 1 ]"
else
  erreur "backup.env absent : étape 7 non réalisée"; ECARTS=$((ECARTS + 1))
fi
verif "UFW : règles 22, 80, 443 uniquement" "[ \"\$(ufw status | grep -E '^(22|80|443)/tcp ' | wc -l)\" -ge 3 ] && [ \"\$(ufw status | grep -E '^[0-9]+/(tcp|udp) ' | grep -vE '^(22|80|443)/tcp' | wc -l)\" -eq 0 ]"
verif "Aucun port public autre que 22, 80, 443 en écoute" "[ \$(ss -Hlnt | awk '{print \$4}' | grep -vE '^(127\\.|\\[::1\\])' | sed 's/.*://' | sort -u | grep -vE '^(22|80|443)$' | wc -l) -eq 0 ]"
verif "fail2ban : prison sshd active" "fail2ban-client status sshd >/dev/null 2>&1"
verif "unattended-upgrades actif" "systemctl is-active --quiet unattended-upgrades"
verif "SSH : mot de passe refusé" "sshd -T | grep -q '^passwordauthentication no'"
verif "SSH : root par clé uniquement" "sshd -T | grep -q '^permitrootlogin prohibit-password'"
verif "Base de données non exposée (aucun port publié sur cms-db)" "[ -z \"\$(docker port affichage-cms-db-1 2>/dev/null)\" ]"
verif "CMS publié sur 127.0.0.1 uniquement" "docker port affichage-cms-web-1 | grep -q '^80/tcp -> 127.0.0.1:8080'"
verif "Documentation présente dans $AFFICHAGE_DIR/DOCS (5 fichiers)" "[ \$(ls $AFFICHAGE_DIR/DOCS/*.md | wc -l) -ge 5 ]"
verif "Fuseau du système Europe/Paris" "[ \$(timedatectl show -p Timezone --value) = Europe/Paris ]"
verif "Fuseau du CMS Europe/Paris" "[ \"\$(mysql_cms \"SELECT \\\`value\\\` FROM setting WHERE setting='defaultTimezone';\")\" = Europe/Paris ]"
verif "Langue du CMS : fr" "[ \"\$(mysql_cms \"SELECT \\\`value\\\` FROM setting WHERE setting='DEFAULT_LANGUAGE';\")\" = fr ]"
# shellcheck disable=SC2034  # ABOUT est lue dans l'expression évaluée par verif()
ABOUT=$(curl -s -H "Host: $AFFICHAGE_DOMAINE" http://127.0.0.1:8080/about/config || true)
verif "Version du CMS : 4.5.2" "[[ \"\$ABOUT\" == *'\"version\":\"4.5.2\"'* ]]"

palier "8 — Résultat automatique : $ECARTS écart(s)"
info "Compléter les contrôles manuels de checklist-recette.md (navigateur, player, SSL Labs, manager OVH, redémarrage)."
[ "$ECARTS" -eq 0 ] || exit 2
