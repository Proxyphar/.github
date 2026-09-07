#!/usr/bin/env bash
# Étape 4 — Installation de Xibo CMS 4.5.2 (Docker) dans /opt/affichage.
#
# - installe Docker Engine (dépôt officiel Docker) avec rotation des journaux ;
# - crée /opt/affichage, génère config.env (droits 600) avec des mots de passe distincts ;
# - démarre la pile avec des images aux tags figés, attend le CMS ;
# - applique la configuration PROXYPHAR (fuseau, langue, XMR, limites, clé CMS) et
#   le compte administrateur (04-cms/configurer-cms.sh) ;
# - copie la documentation dans /opt/affichage/DOCS.
#
# Usage : sudo ./installer-cms.sh [--forcer]
#   --forcer : accepte de réutiliser un /opt/affichage/config.env existant (réinstallation)
#
# Les mots de passe sont affichés UNE SEULE FOIS en fin de script.

KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/common.sh
. "$KIT_DIR/lib/common.sh"

FORCER=0
for arg in "$@"; do
  case "$arg" in
    --forcer) FORCER=1 ;;
    --aide|-h|--help) sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) fatal "Option inconnue : $arg" ;;
  esac
done
exiger_root
export DEBIAN_FRONTEND=noninteractive

palier "4 — Installation de Xibo CMS 4.5.2"

# --- Garde-fous ---------------------------------------------------------------------
. /etc/os-release
[ "${VERSION_ID:-}" = "24.04" ] || fatal "Ce kit cible Ubuntu 24.04 (trouvé : ${VERSION_ID:-?})"
if [ -f "$AFFICHAGE_DIR/config.env" ] && [ "$FORCER" -eq 0 ]; then
  fatal "$AFFICHAGE_DIR/config.env existe déjà. Relancer avec --forcer pour le conserver, ou le supprimer pour repartir de zéro."
fi
if [ -d "$AFFICHAGE_DIR/shared/db" ] && [ -n "$(ls -A "$AFFICHAGE_DIR/shared/db" 2>/dev/null)" ] && [ "$FORCER" -eq 0 ]; then
  fatal "$AFFICHAGE_DIR/shared/db contient déjà une base : ce n'est pas une installation vierge."
fi

# --- Docker Engine (dépôt officiel) -------------------------------------------------
if ! command -v docker >/dev/null 2>&1; then
  info "Installation de Docker Engine depuis download.docker.com"
  apt-get update -qq
  apt-get install -y -qq ca-certificates curl gnupg >/dev/null
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc
  printf 'deb [arch=%s signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu %s stable\n' \
    "$(dpkg --print-architecture)" "${UBUNTU_CODENAME:-noble}" > /etc/apt/sources.list.d/docker.list
  apt-get update -qq
  apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-compose-plugin >/dev/null
fi
install -d /etc/docker
if ! cmp -s "$KIT_DIR/04-cms/daemon.json" /etc/docker/daemon.json 2>/dev/null; then
  cp "$KIT_DIR/04-cms/daemon.json" /etc/docker/daemon.json
  systemctl restart docker
fi
systemctl enable --now docker >/dev/null
docker compose version >/dev/null || fatal "Le greffon docker compose est absent"
ok "Docker $(docker version --format '{{.Server.Version}}') ; compose $(docker compose version --short)"

# --- Arborescence /opt/affichage -------------------------------------------------------
install -d -m 750 "$AFFICHAGE_DIR"
install -d "$AFFICHAGE_DIR"/shared/{db,backup} "$AFFICHAGE_DIR"/shared/cms/{custom,library,web/userscripts,ca-certs}
install -d "$AFFICHAGE_DIR"/{DOCS,bin,backups}
cp "$KIT_DIR/04-cms/docker-compose.yml" "$AFFICHAGE_DIR/docker-compose.yml"
cp "$KIT_DIR/04-cms/settings-custom.php" "$AFFICHAGE_DIR/shared/cms/custom/settings-custom.php"
cp "$KIT_DIR"/09-docs/*.md "$AFFICHAGE_DIR/DOCS/"
ok "Arborescence créée dans $AFFICHAGE_DIR (DOCS copiée)"

# --- config.env ---------------------------------------------------------------------
if [ ! -f "$AFFICHAGE_DIR/config.env" ]; then
  MYSQL_PW=$(mot_de_passe_alnum 32)
  ADMIN_PW=$(mot_de_passe_fort 24)
  HOTLINE_PW=$(mot_de_passe_fort 20)
  CMS_KEY=$(mot_de_passe_alnum 16)
  sed -e "s|__MYSQL_PASSWORD__|$MYSQL_PW|" \
      -e "s|__AFFICHAGE_ADMIN_PASSWORD__|$ADMIN_PW|" \
      -e "s|__AFFICHAGE_HOTLINE_PASSWORD__|$HOTLINE_PW|" \
      -e "s|__AFFICHAGE_CMS_KEY__|$CMS_KEY|" \
      "$KIT_DIR/04-cms/config.env.template" > "$AFFICHAGE_DIR/config.env"
  ok "config.env généré (mots de passe distincts pour la base, l'administrateur et la hotline)"
else
  info "config.env existant conservé (--forcer)"
fi
chown root:root "$AFFICHAGE_DIR/config.env"
chmod 600 "$AFFICHAGE_DIR/config.env"
grep -q '^MYSQL_PASSWORD=.\{16,\}' "$AFFICHAGE_DIR/config.env" || fatal "MYSQL_PASSWORD absent ou trop court dans config.env"

# --- Images et démarrage ------------------------------------------------------------
info "Téléchargement des images (tags figés)"
compose pull --quiet
info "Empreintes des images téléchargées :"
for img in $(compose config --images); do
  printf '    %-48s %s\n' "$img" "$(docker image inspect --format '{{index .RepoDigests 0}}' "$img" | sed 's/.*@//')"
done | tee "$AFFICHAGE_DIR/DOCS/empreintes-images.txt"
compose up -d
info "Attente du CMS (première initialisation de la base : plusieurs minutes)"
if attendre_cms http://127.0.0.1:8080/login 300; then
  ok "Le CMS répond sur 127.0.0.1:8080"
else
  erreur "Le CMS ne répond pas après 10 minutes. Journaux :"
  compose logs --tail=50 cms-web cms-db
  exit 2
fi

# --- Configuration PROXYPHAR et compte administrateur -------------------------------
"$KIT_DIR/04-cms/configurer-cms.sh"

# --- Compte rendu -------------------------------------------------------------------
charger_config_env
ADMIN_USER=$(grep -E '^# AFFICHAGE_ADMIN_USER=' "$AFFICHAGE_DIR/config.env" | cut -d= -f2-)
ADMIN_PW=$(grep -E '^# AFFICHAGE_ADMIN_PASSWORD=' "$AFFICHAGE_DIR/config.env" | cut -d= -f2-)
CMS_KEY=$(grep -E '^# AFFICHAGE_CMS_KEY=' "$AFFICHAGE_DIR/config.env" | cut -d= -f2-)
palier "4 — Résultat"
cat <<FIN
Xibo CMS 4.5.2 est installé dans $AFFICHAGE_DIR. État des conteneurs :
$(compose ps --format '    {{.Name}}  {{.Image}}  {{.Status}}')

Identifiants — À TRANSMETTRE UNE SEULE FOIS À ALEXANDRE, PUIS FERMER CE TERMINAL
(ils restent lisibles par root dans $AFFICHAGE_DIR/config.env, droits 600) :
    Mot de passe base MySQL (cms) : $MYSQL_PASSWORD
    Administrateur CMS            : $ADMIN_USER / $ADMIN_PW
    Clé CMS (enrôlement players)  : $CMS_KEY
Le compte hotline sera créé à l'étape 6 (06-identite/creer-comptes.sh).

Le CMS n'est pas encore joignable de l'extérieur : passer à l'étape 5 (05-nginx-tls).
FIN
