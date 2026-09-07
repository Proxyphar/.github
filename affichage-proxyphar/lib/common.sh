#!/usr/bin/env bash
# Fonctions communes au kit de déploiement Xibo PROXYPHAR.
# Ce fichier est « sourcé » par les scripts du kit ; il ne s'exécute pas seul.

set -o errexit
set -o nounset
set -o pipefail

AFFICHAGE_DIR="${AFFICHAGE_DIR:-/opt/affichage}"
AFFICHAGE_DOMAINE="${AFFICHAGE_DOMAINE:-intranet.proxyphar.fr}"
# Adresses du VPS : à remplacer par celles du VPS neuf dès sa livraison (voir GUIDE-EXECUTION.md).
AFFICHAGE_IPV4="${AFFICHAGE_IPV4:-51.75.251.209}"
AFFICHAGE_IPV6="${AFFICHAGE_IPV6:-2001:41d0:305:2100::a4c4}"
AFFICHAGE_ADMIN_OS="${AFFICHAGE_ADMIN_OS:-proxyadmin}"
AFFICHAGE_LOG="${AFFICHAGE_LOG:-/var/log/affichage-kit.log}"

# Couleurs uniquement si la sortie est un terminal.
if [ -t 1 ]; then
  C_VERT=$'\033[32m'; C_ROUGE=$'\033[31m'; C_JAUNE=$'\033[33m'; C_BLEU=$'\033[34m'; C_FIN=$'\033[0m'
else
  C_VERT=''; C_ROUGE=''; C_JAUNE=''; C_BLEU=''; C_FIN=''
fi

_horodatage() { date '+%Y-%m-%d %H:%M:%S'; }

_journal() {
  # Journalise dans le fichier de log si accessible en écriture, sinon ignore.
  if [ -w "$(dirname "$AFFICHAGE_LOG")" ] 2>/dev/null; then
    printf '%s %s %s\n' "$(_horodatage)" "$1" "$2" >> "$AFFICHAGE_LOG" 2>/dev/null || true
  fi
}

info()  { printf '%s[INFO]%s  %s\n' "$C_BLEU" "$C_FIN" "$*";  _journal INFO "$*"; }
ok()    { printf '%s[OK]%s    %s\n' "$C_VERT" "$C_FIN" "$*";  _journal OK "$*"; }
alerte(){ printf '%s[ALERTE]%s %s\n' "$C_JAUNE" "$C_FIN" "$*" >&2; _journal ALERTE "$*"; }
erreur(){ printf '%s[ERREUR]%s %s\n' "$C_ROUGE" "$C_FIN" "$*" >&2; _journal ERREUR "$*"; }
fatal() { erreur "$*"; exit 1; }

palier() {
  # Affiche un titre de palier, à recopier dans le compte rendu.
  printf '\n%s========== PALIER : %s ==========%s\n' "$C_BLEU" "$*" "$C_FIN"
  _journal PALIER "$*"
}

exiger_root() {
  if [ "$(id -u)" -ne 0 ]; then
    fatal "Ce script doit être lancé en root (sudo -i, puis relancer)."
  fi
}

exiger_commande() {
  local c
  for c in "$@"; do
    command -v "$c" >/dev/null 2>&1 || fatal "Commande absente : $c"
  done
}

confirmer() {
  # Demande une confirmation explicite ; refuse par défaut.
  # Usage : confirmer "Question ?" || exit 0
  local reponse
  printf '%s%s%s [oui/NON] : ' "$C_JAUNE" "$1" "$C_FIN"
  read -r reponse
  [ "$reponse" = "oui" ]
}

charger_config_env() {
  # Charge /opt/affichage/config.env dans l'environnement du script (sans l'afficher).
  local fichier="${1:-$AFFICHAGE_DIR/config.env}"
  [ -f "$fichier" ] || fatal "Fichier introuvable : $fichier"
  set -o allexport
  # shellcheck disable=SC1090
  . "$fichier"
  set +o allexport
}

_aleatoire() {
  # Chaîne aléatoire de $1 caractères pris dans le jeu $2, sans « | head » après tr :
  # avec « pipefail », head fermerait le tube et ferait échouer la fonction (SIGPIPE).
  local longueur="$1" jeu="$2" resultat=""
  while [ "${#resultat}" -lt "$longueur" ]; do
    resultat="$resultat$(head -c 4096 /dev/urandom | LC_ALL=C tr -dc "$jeu")"
  done
  printf '%s' "${resultat:0:$longueur}"
}

mot_de_passe_alnum() {
  # Mot de passe alphanumérique (exigence Xibo pour le mot de passe MySQL).
  _aleatoire "${1:-32}" 'A-Za-z0-9'
}

mot_de_passe_fort() {
  # Mot de passe avec un jeu de symboles sans ambiguïté et sans caractère gênant dans un
  # shell, un fichier env ou une expression sed (le « - » est en fin de jeu : pas de plage).
  _aleatoire "${1:-24}" 'A-Za-z0-9!#%+=_.-'
}

compose() {
  # Enveloppe docker compose sur le projet Xibo.
  ( cd "$AFFICHAGE_DIR" && docker compose "$@" )
}

mysql_cms() {
  # Exécute une requête SQL sur la base du CMS, en lisant le mot de passe depuis config.env.
  # Usage : mysql_cms "SELECT ..."   ou   mysql_cms < fichier.sql
  [ -n "${MYSQL_PASSWORD:-}" ] || charger_config_env
  if [ $# -gt 0 ]; then
    compose exec -T -e MYSQL_PWD="$MYSQL_PASSWORD" cms-db mysql --batch --skip-column-names -u cms cms -e "$1"
  else
    compose exec -T -e MYSQL_PWD="$MYSQL_PASSWORD" cms-db mysql --batch --skip-column-names -u cms cms
  fi
}

attendre_cms() {
  # Attend que le CMS réponde (page de connexion) sur l'adresse locale.
  local url="${1:-http://127.0.0.1:8080/login}"
  local max="${2:-180}"
  local code
  for _ in $(seq 1 "$max"); do
    code=$(curl -s -o /dev/null -w '%{http_code}' -H "Host: $AFFICHAGE_DOMAINE" "$url" || true)
    case "$code" in 200|302) return 0 ;; esac
    sleep 2
  done
  return 1
}
