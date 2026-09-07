#!/usr/bin/env bash
# Étape 7 — Mise en place de la sauvegarde quotidienne externe et test de restauration.
#
# - installe rclone et rsync, copie affichage-backup.sh / affichage-restore.sh dans /opt/affichage/bin ;
# - crée /opt/affichage/backup.env (600) à compléter avec le remote rclone ;
# - installe la minuterie systemd (03:15 Europe/Paris) ;
# - avec --executer : lance une première sauvegarde puis un test de restauration sur copie.
#
# Usage : sudo ./installer-sauvegarde.sh [--remote NOM:chemin] [--executer]
#   --remote    valeur de BACKUP_REMOTE (ex. proxyphar-backup:affichage-intranet) ; le remote
#               doit avoir été créé avec « rclone config » (identifiants hors dépôt)
#   --executer  sauvegarde immédiate + restauration de test (peut prendre plusieurs minutes)

KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/common.sh
. "$KIT_DIR/lib/common.sh"
REMOTE=""; EXECUTER=0
while [ $# -gt 0 ]; do
  case "$1" in
    --remote) REMOTE="$2"; shift 2 ;;
    --executer) EXECUTER=1; shift ;;
    --aide|-h|--help) sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) fatal "Option inconnue : $1" ;;
  esac
done
exiger_root
export DEBIAN_FRONTEND=noninteractive

palier "7 — Sauvegarde externe"
apt-get install -y -qq rclone rsync >/dev/null
install -d -m 750 "$AFFICHAGE_DIR/bin" "$AFFICHAGE_DIR/backups"
install -m 750 "$KIT_DIR/07-sauvegarde/affichage-backup.sh" "$AFFICHAGE_DIR/bin/affichage-backup.sh"
install -m 750 "$KIT_DIR/07-sauvegarde/affichage-restore.sh" "$AFFICHAGE_DIR/bin/affichage-restore.sh"
if [ ! -f "$AFFICHAGE_DIR/backup.env" ]; then
  install -m 600 "$KIT_DIR/07-sauvegarde/backup.env.template" "$AFFICHAGE_DIR/backup.env"
fi
if [ -n "$REMOTE" ]; then
  sed -i "s|^BACKUP_REMOTE=.*|BACKUP_REMOTE=$REMOTE|" "$AFFICHAGE_DIR/backup.env"
fi
chmod 600 "$AFFICHAGE_DIR/backup.env"
install -m 644 "$KIT_DIR/07-sauvegarde/affichage-backup.service" /etc/systemd/system/affichage-backup.service
install -m 644 "$KIT_DIR/07-sauvegarde/affichage-backup.timer" /etc/systemd/system/affichage-backup.timer
systemctl daemon-reload
systemctl enable --now affichage-backup.timer >/dev/null
ok "Minuterie installée : $(systemctl list-timers affichage-backup.timer --no-legend | awk '{print $1, $2, $3}')"

REMOTE_CFG=$(sed -n 's/^BACKUP_REMOTE=//p' "$AFFICHAGE_DIR/backup.env")
if [ -z "$REMOTE_CFG" ]; then
  alerte "BACKUP_REMOTE est vide : créer le remote (rclone config) puis relancer avec --remote NOM:chemin"
  info "Sans destination externe, seul l'export SQL local sera réalisé : la sauvegarde ne sera PAS conforme."
else
  if rclone lsd "${REMOTE_CFG%%:*}:" >/dev/null 2>&1; then
    ok "Destination externe joignable : $REMOTE_CFG"
    rclone mkdir "$REMOTE_CFG" >/dev/null 2>&1 || true
  else
    erreur "Le remote rclone « ${REMOTE_CFG%%:*} » ne répond pas : vérifier « rclone config » (identifiants) puis relancer"
    exit 2
  fi
fi

if [ "$EXECUTER" -eq 1 ]; then
  palier "7b — Première sauvegarde"
  if [ -n "$REMOTE_CFG" ]; then "$AFFICHAGE_DIR/bin/affichage-backup.sh"; else "$AFFICHAGE_DIR/bin/affichage-backup.sh" --sans-externe; fi
  palier "7c — Test de restauration sur copie"
  RAM_DISPO=$(free -m | awk '/^Mem:/ {print $7}')
  [ "$RAM_DISPO" -ge 1500 ] || alerte "Mémoire disponible faible (${RAM_DISPO} Mo) : le test peut être lent"
  if [ -n "$REMOTE_CFG" ]; then
    "$AFFICHAGE_DIR/bin/affichage-restore.sh" --sauvegarde derniere --source rclone
  else
    "$AFFICHAGE_DIR/bin/affichage-restore.sh" --sauvegarde derniere --source local
  fi
  info "La copie restaurée répond sur http://127.0.0.1:8081 (tunnel SSH pour la consulter : ssh -L 8081:127.0.0.1:8081 ...)"
  info "Une fois contrôlée, la supprimer : $AFFICHAGE_DIR/bin/affichage-restore.sh --nettoyer"
fi

palier "7 — Résultat"
cat <<FIN
Sauvegarde quotidienne : $AFFICHAGE_DIR/bin/affichage-backup.sh (journal : /var/log/affichage-backup.log,
état : $AFFICHAGE_DIR/backups/DERNIER-ETAT). Restauration : $AFFICHAGE_DIR/bin/affichage-restore.sh --aide.
Le Backup automatisé OVH est à vérifier dans le manager (VPS > Sauvegarde automatisée : « Activé »).
Étape suivante : 08-recette.
FIN
