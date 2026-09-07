#!/usr/bin/env bash
# Étape 2 — Durcissement de base du VPS.
#
# - crée l'utilisateur d'administration « proxyadmin » (sudo, clé SSH) ;
# - SSH : PasswordAuthentication no, PermitRootLogin prohibit-password ;
# - pare-feu UFW : 22, 80, 443 entrants uniquement ;
# - fail2ban (sshd) et unattended-upgrades (mises à jour de sécurité).
#
# Usage : sudo ./durcir.sh [--cle-publique FICHIER.pub] [--redemarrage-auto]
#   --cle-publique    fichier de clé publique à installer pour proxyadmin
#                     (par défaut : authorized_keys de l'utilisateur qui a lancé sudo)
#   --redemarrage-auto autorise unattended-upgrades à redémarrer à 04:30 si nécessaire
#
# Le script ne verrouille PAS l'utilisateur OVH par défaut (« ubuntu ») : testez
# d'abord la connexion proxyadmin dans un second terminal, puis lancez :
#   sudo ./durcir.sh --verrouiller-utilisateur ubuntu

KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/common.sh
. "$KIT_DIR/lib/common.sh"

CLE_PUB=""
REDEMARRAGE_AUTO=0
VERROUILLER=""
while [ $# -gt 0 ]; do
  case "$1" in
    --cle-publique) CLE_PUB="$2"; shift 2 ;;
    --redemarrage-auto) REDEMARRAGE_AUTO=1; shift ;;
    --verrouiller-utilisateur) VERROUILLER="$2"; shift 2 ;;
    --aide|-h|--help) sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) fatal "Option inconnue : $1 (voir --aide)" ;;
  esac
done

exiger_root
export DEBIAN_FRONTEND=noninteractive

# --- Mode verrouillage d'un compte (second passage) ------------------------------
if [ -n "$VERROUILLER" ]; then
  palier "2b — Verrouillage du compte $VERROUILLER"
  id "$VERROUILLER" >/dev/null 2>&1 || fatal "Utilisateur inconnu : $VERROUILLER"
  [ "$VERROUILLER" != "$AFFICHAGE_ADMIN_OS" ] || fatal "Refus : $AFFICHAGE_ADMIN_OS est le compte d'administration"
  confirmer "Confirmez-vous avoir testé la connexion SSH avec $AFFICHAGE_ADMIN_OS ?" || exit 0
  passwd -l "$VERROUILLER" >/dev/null
  if [ -f "/home/$VERROUILLER/.ssh/authorized_keys" ]; then
    mv "/home/$VERROUILLER/.ssh/authorized_keys" "/home/$VERROUILLER/.ssh/authorized_keys.desactive"
  fi
  ok "Compte $VERROUILLER verrouillé (mot de passe et clés SSH désactivés)"
  exit 0
fi

palier "2 — Durcissement de base"

# --- Clé publique à installer ------------------------------------------------------
if [ -z "$CLE_PUB" ]; then
  if [ -n "${SUDO_USER:-}" ] && [ -f "/home/$SUDO_USER/.ssh/authorized_keys" ]; then
    CLE_PUB="/home/$SUDO_USER/.ssh/authorized_keys"
  elif [ -f /root/.ssh/authorized_keys ]; then
    CLE_PUB=/root/.ssh/authorized_keys
  fi
fi
[ -n "$CLE_PUB" ] && [ -s "$CLE_PUB" ] || fatal "Aucune clé publique trouvée : indiquer --cle-publique FICHIER.pub"
# Ne garder que les lignes de clés (pas les commandes forcées OVH/cloud-init).
CLES=$(grep -E '^(ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp256|sk-ssh-ed25519@openssh.com) ' "$CLE_PUB" || true)
[ -n "$CLES" ] || fatal "Aucune clé exploitable dans $CLE_PUB"
info "Clé(s) publique(s) retenue(s) :"
printf '%s\n' "$CLES" | awk '{print "    " $1, substr($2,1,20) "...", $3}'

# --- Utilisateur d'administration ---------------------------------------------------
if id "$AFFICHAGE_ADMIN_OS" >/dev/null 2>&1; then
  info "Utilisateur $AFFICHAGE_ADMIN_OS déjà présent"
else
  adduser --disabled-password --gecos "Administration Xibo PROXYPHAR" "$AFFICHAGE_ADMIN_OS" >/dev/null
  ok "Utilisateur $AFFICHAGE_ADMIN_OS créé (sans mot de passe)"
fi
usermod -aG sudo "$AFFICHAGE_ADMIN_OS"
install -d -m 700 -o "$AFFICHAGE_ADMIN_OS" -g "$AFFICHAGE_ADMIN_OS" "/home/$AFFICHAGE_ADMIN_OS/.ssh"
printf '%s\n' "$CLES" > "/home/$AFFICHAGE_ADMIN_OS/.ssh/authorized_keys"
chmod 600 "/home/$AFFICHAGE_ADMIN_OS/.ssh/authorized_keys"
chown "$AFFICHAGE_ADMIN_OS:$AFFICHAGE_ADMIN_OS" "/home/$AFFICHAGE_ADMIN_OS/.ssh/authorized_keys"
# sudo sans mot de passe : le compte n'a pas de mot de passe (accès par clé uniquement).
printf '%s ALL=(ALL) NOPASSWD:ALL\n' "$AFFICHAGE_ADMIN_OS" > "/etc/sudoers.d/90-$AFFICHAGE_ADMIN_OS"
chmod 440 "/etc/sudoers.d/90-$AFFICHAGE_ADMIN_OS"
visudo -cf "/etc/sudoers.d/90-$AFFICHAGE_ADMIN_OS" >/dev/null || fatal "Fichier sudoers invalide"
ok "$AFFICHAGE_ADMIN_OS : sudo actif, clé SSH installée"

# Clé de secours pour root (autorisé par clé uniquement : prohibit-password).
install -d -m 700 /root/.ssh
printf '%s\n' "$CLES" > /root/.ssh/authorized_keys
chmod 600 /root/.ssh/authorized_keys
ok "Même clé installée pour root (secours, clé uniquement)"

# --- SSH ------------------------------------------------------------------------------
install -d /etc/ssh/sshd_config.d
cat > /etc/ssh/sshd_config.d/00-proxyphar.conf <<'SSHEOF'
# Durcissement PROXYPHAR — ce fichier est lu avant les autres (ordre lexical) :
# la première valeur rencontrée pour une directive l'emporte.
PasswordAuthentication no
KbdInteractiveAuthentication no
ChallengeResponseAuthentication no
PermitRootLogin prohibit-password
PubkeyAuthentication yes
PermitEmptyPasswords no
MaxAuthTries 4
LoginGraceTime 30
X11Forwarding no
ClientAliveInterval 300
ClientAliveCountMax 2
UsePAM yes
SSHEOF
sshd -t || fatal "Configuration SSH invalide : aucun redémarrage effectué"
systemctl restart ssh
ok "SSH : mot de passe refusé, root par clé uniquement (sshd -t validé)"

# --- UFW ------------------------------------------------------------------------------
apt-get install -y -qq ufw >/dev/null
sed -i 's/^IPV6=.*/IPV6=yes/' /etc/default/ufw
ufw --force reset >/dev/null
ufw default deny incoming >/dev/null
ufw default allow outgoing >/dev/null
ufw limit 22/tcp comment 'SSH (limite anti-bruteforce)' >/dev/null
ufw allow 80/tcp comment 'HTTP (redirection + ACME)' >/dev/null
ufw allow 443/tcp comment 'HTTPS CMS Xibo' >/dev/null
ufw --force enable >/dev/null
ok "UFW actif : entrant limité à 22, 80, 443 (IPv4 et IPv6)"
ufw status verbose | sed 's/^/    /'

# --- fail2ban ---------------------------------------------------------------------------
apt-get install -y -qq fail2ban >/dev/null
cat > /etc/fail2ban/jail.d/proxyphar.local <<'F2BEOF'
[DEFAULT]
bantime  = 1h
findtime = 10m
maxretry = 5
backend  = systemd

[sshd]
enabled = true
mode    = aggressive

[recidive]
enabled  = true
bantime  = 1w
findtime = 1d
maxretry = 3
F2BEOF
systemctl enable --now fail2ban >/dev/null
systemctl restart fail2ban
ok "fail2ban actif (prisons sshd et recidive)"

# --- unattended-upgrades ----------------------------------------------------------------
apt-get install -y -qq unattended-upgrades apt-listchanges >/dev/null
cat > /etc/apt/apt.conf.d/20auto-upgrades <<'APTEOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::AutocleanInterval "7";
APT::Periodic::Unattended-Upgrade "1";
APTEOF
if [ "$REDEMARRAGE_AUTO" -eq 1 ]; then REBOOT="true"; else REBOOT="false"; fi
cat > /etc/apt/apt.conf.d/52proxyphar-unattended <<APTEOF
// Mises à jour de sécurité Ubuntu uniquement (les dépôts Docker sont mis à jour
// manuellement lors des fenêtres de maintenance, voir 09-docs/04-mise-a-jour-cms.md).
Unattended-Upgrade::Allowed-Origins {
    "\${distro_id}:\${distro_codename}-security";
    "\${distro_id}ESMApps:\${distro_codename}-apps-security";
    "\${distro_id}ESM:\${distro_codename}-infra-security";
};
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "$REBOOT";
Unattended-Upgrade::Automatic-Reboot-Time "04:30";
APTEOF
systemctl enable --now unattended-upgrades >/dev/null
unattended-upgrade --dry-run -d >/dev/null 2>&1 && ok "unattended-upgrades actif (redémarrage automatique : $REBOOT)" \
  || alerte "unattended-upgrades installé mais le test à blanc a signalé un problème (voir /var/log/unattended-upgrades/)"

# --- Divers -----------------------------------------------------------------------------
# Pas de service d'administration exposé : vérification qu'aucun port autre que 22 n'écoute publiquement.
info "Ports en écoute (hors localhost) :"
ss -Hlntu | awk '$5 !~ /^(127\.|\[::1\])/ {print "    " $1, $5}' | sort -u

palier "2 — Résultat"
cat <<FIN
Durcissement appliqué. AVANT de fermer cette session :
  1. Ouvrez un second terminal et testez :  ssh -i ~/.ssh/proxyphar-affichage $AFFICHAGE_ADMIN_OS@$AFFICHAGE_IPV4
  2. Vérifiez que « sudo -i » fonctionne dans cette nouvelle session.
  3. Verrouillez ensuite le compte fourni par OVH :
       sudo /opt/affichage-kit/02-durcissement/durcir.sh --verrouiller-utilisateur ubuntu
Passer ensuite à l'étape 3 (03-dns).
FIN
