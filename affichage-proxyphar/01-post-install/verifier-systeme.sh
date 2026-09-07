#!/usr/bin/env bash
# Étape 1 — Vérification (et mise en conformité) du système après réinstallation.
#
# Vérifie : version d'Ubuntu et du noyau, espace disque, synchronisation de l'heure,
# fuseau Europe/Paris, locale fr_FR.UTF-8, mémoire et swap.
# Avec --corriger : applique fuseau, locale, NTP et crée un swap de 2 Go si absent.
#
# Usage : sudo ./verifier-systeme.sh [--corriger]

KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/common.sh
. "$KIT_DIR/lib/common.sh"

CORRIGER=0
for arg in "$@"; do
  case "$arg" in
    --corriger) CORRIGER=1 ;;
    --aide|-h|--help)
      sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) fatal "Option inconnue : $arg (voir --aide)" ;;
  esac
done

exiger_root
ECARTS=0

palier "1 — Système après réinstallation ($(hostname))"

# --- Distribution et noyau -----------------------------------------------------
. /etc/os-release
info "Distribution : $PRETTY_NAME"
if [ "${VERSION_ID:-}" = "24.04" ]; then
  ok "Ubuntu 24.04 LTS confirmé"
else
  erreur "Version attendue 24.04, trouvée : ${VERSION_ID:-inconnue}"
  ECARTS=$((ECARTS + 1))
fi
info "Noyau : $(uname -r) (démarré le $(uptime -s))"

# --- Disque ---------------------------------------------------------------------
info "Espace disque racine :"
df -h / | sed 's/^/    /'
TAILLE_GO=$(df -BG --output=size / | tail -1 | tr -dc '0-9')
if [ "$TAILLE_GO" -ge 70 ]; then
  ok "Disque racine de ${TAILLE_GO} Go (gabarit 80 Go attendu)"
else
  alerte "Disque racine de ${TAILLE_GO} Go : inférieur aux 80 Go annoncés, vérifier le gabarit"
  ECARTS=$((ECARTS + 1))
fi

# --- Mémoire et swap ------------------------------------------------------------
RAM_MO=$(free -m | awk '/^Mem:/ {print $2}')
info "Mémoire : ${RAM_MO} Mo ; processeurs : $(nproc)"
if [ "$RAM_MO" -lt 3500 ]; then
  alerte "Moins de 4 Go de RAM détectés (${RAM_MO} Mo) : écart avec le gabarit annoncé"
  ECARTS=$((ECARTS + 1))
fi
if [ -n "$(swapon --show --noheadings)" ]; then
  ok "Swap présent : $(swapon --show --noheadings | awk '{print $1, $3}')"
else
  if [ "$CORRIGER" -eq 1 ]; then
    info "Création d'un fichier de swap de 2 Go (/swapfile)"
    fallocate -l 2G /swapfile && chmod 600 /swapfile && mkswap /swapfile >/dev/null && swapon /swapfile
    grep -q '^/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
    printf 'vm.swappiness = 10\n' > /etc/sysctl.d/60-proxyphar-swap.conf
    sysctl -q -p /etc/sysctl.d/60-proxyphar-swap.conf
    ok "Swap de 2 Go activé (swappiness 10)"
  else
    alerte "Aucun swap : recommandé sur 4 Go de RAM (relancer avec --corriger)"
  fi
fi

# --- Heure, NTP, fuseau ---------------------------------------------------------
if [ "$CORRIGER" -eq 1 ]; then
  timedatectl set-timezone Europe/Paris
  timedatectl set-ntp true 2>/dev/null || alerte "timedatectl set-ntp a échoué (service NTP absent ?)"
  systemctl enable --now systemd-timesyncd >/dev/null 2>&1 || true
fi
FUSEAU=$(timedatectl show -p Timezone --value)
NTP_SYNC=$(timedatectl show -p NTPSynchronized --value)
info "Date/heure : $(date '+%d/%m/%Y %H:%M:%S %Z')"
if [ "$FUSEAU" = "Europe/Paris" ]; then ok "Fuseau Europe/Paris"; else
  erreur "Fuseau actuel : $FUSEAU (attendu Europe/Paris ; relancer avec --corriger)"; ECARTS=$((ECARTS + 1)); fi
if [ "$NTP_SYNC" = "yes" ]; then ok "Heure synchronisée (NTP)"; else
  alerte "Heure non synchronisée (NTPSynchronized=$NTP_SYNC) ; attendre une minute après --corriger, puis revérifier"
  ECARTS=$((ECARTS + 1)); fi

# --- Locale ---------------------------------------------------------------------
if [ "$CORRIGER" -eq 1 ]; then
  export DEBIAN_FRONTEND=noninteractive
  apt-get install -y -qq locales >/dev/null
  sed -i 's/^# *fr_FR.UTF-8 UTF-8/fr_FR.UTF-8 UTF-8/' /etc/locale.gen
  grep -q '^fr_FR.UTF-8 UTF-8' /etc/locale.gen || echo 'fr_FR.UTF-8 UTF-8' >> /etc/locale.gen
  locale-gen >/dev/null
  update-locale LANG=fr_FR.UTF-8 LC_TIME=fr_FR.UTF-8
fi
if grep -qi '^fr_FR.utf8$' <<< "$(locale -a 2>/dev/null)"; then
  ok "Locale fr_FR.UTF-8 disponible ($(grep '^LANG=' /etc/default/locale 2>/dev/null || echo 'LANG non défini'))"
else
  erreur "Locale fr_FR.UTF-8 absente (relancer avec --corriger)"; ECARTS=$((ECARTS + 1))
fi

# --- Réseau ---------------------------------------------------------------------
IP4=$(ip -4 -o addr show scope global | awk 'NR==1 {print $4}')
IP6=$(ip -6 -o addr show scope global | awk 'NR==1 {print $4}')
info "Adresse IPv4 : ${IP4:-aucune} ; IPv6 : ${IP6:-aucune}"
if [ "${IP4%/*}" = "$AFFICHAGE_IPV4" ]; then ok "IPv4 conforme à l'inventaire ($AFFICHAGE_IPV4)"; else
  alerte "IPv4 différente de l'inventaire ($AFFICHAGE_IPV4) : signaler l'écart"; ECARTS=$((ECARTS + 1)); fi
if [ -z "$IP6" ]; then
  alerte "Pas d'IPv6 globale configurée : l'enregistrement AAAA ne devra pas être créé tant que l'IPv6 n'est pas active (voir 03-dns)"
fi

# --- Traces d'une installation précédente ---------------------------------------
if [ -d /opt/affichage ] || docker ps >/dev/null 2>&1; then
  alerte "Un dossier /opt/affichage ou un démon Docker existe déjà : le système ne semble pas vierge"
  ECARTS=$((ECARTS + 1))
else
  ok "Aucune trace de Docker ni de /opt/affichage : système vierge"
fi
if grep -rqi 'bubu' /etc/hostname /etc/hosts /etc/nginx /etc/apache2 /home /root 2>/dev/null; then
  erreur "Chaîne « bubu » trouvée dans la configuration système : à examiner"
  ECARTS=$((ECARTS + 1))
else
  ok "Aucune mention « bubu » dans /etc, /home, /root"
fi

# --- Mises à jour ---------------------------------------------------------------
if [ "$CORRIGER" -eq 1 ]; then
  info "Mise à jour des paquets (apt-get update && upgrade)"
  apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get upgrade -y -qq >/dev/null
  ok "Paquets à jour"
  if [ -f /var/run/reboot-required ]; then
    alerte "Un redémarrage est requis par les mises à jour : exécuter 'reboot' avant l'étape 2"
  fi
fi

palier "1 — Résultat : $ECARTS écart(s)"
if [ "$ECARTS" -eq 0 ]; then
  ok "Système conforme. Passer à l'étape 2 (02-durcissement/durcir.sh)."
else
  alerte "Corriger ou signaler les écarts ci-dessus avant de continuer."
  exit 2
fi
