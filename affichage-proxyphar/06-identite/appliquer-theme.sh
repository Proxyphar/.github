#!/usr/bin/env bash
# Étape 6a — Identité PROXYPHAR sur le CMS (Xibo 4.5 : dossier library/brand/).
#
# Copie dans /opt/affichage/shared/cms/library/brand/ :
#   config.json (nom de l'application, titre, lien d'assistance, texte « À propos »),
#   theme.css (couleurs), logo.svg, logo-dark.svg, logo-icon.svg, favicon.ico,
#   192x192.png, 512x512.png ; puis redémarre le CMS et vérifie via /about/config.
#
# Usage : sudo ./appliquer-theme.sh [--source DOSSIER]
#   --source  dossier contenant les fichiers de la charte (par défaut : 06-identite/brand,
#             reproduction vectorielle du logo PROXYPHAR aux couleurs officielles)

KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/common.sh
. "$KIT_DIR/lib/common.sh"
SOURCE="$KIT_DIR/06-identite/brand"
while [ $# -gt 0 ]; do
  case "$1" in
    --source) SOURCE="$2"; shift 2 ;;
    --aide|-h|--help) sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) fatal "Option inconnue : $1" ;;
  esac
done
exiger_root
# Les visuels bitmap (favicon.ico, 192x192.png, 512x512.png) ne sont pas versionnés :
# ils sont générés ici, aux couleurs du logo, s'ils manquent.
if [ "$SOURCE" = "$KIT_DIR/06-identite/brand" ]; then
  for f in favicon.ico 192x192.png 512x512.png; do
    if [ ! -f "$SOURCE/$f" ]; then
      python3 "$KIT_DIR/06-identite/generer-placeholders.py" "$SOURCE" >/dev/null
      break
    fi
  done
fi
BRAND="$AFFICHAGE_DIR/shared/cms/library/brand"
[ -d "$BRAND" ] || fatal "$BRAND absent : le CMS n'a pas encore démarré (étape 4)"
[ -f "$SOURCE/config.json" ] || fatal "config.json introuvable dans $SOURCE"

palier "6a — Thème PROXYPHAR"
python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$SOURCE/config.json" || fatal "config.json invalide"

for f in config.json theme.css logo.svg logo-dark.svg logo-icon.svg favicon.ico 192x192.png 512x512.png; do
  if [ -f "$SOURCE/$f" ]; then
    install -m 644 "$SOURCE/$f" "$BRAND/$f"
    # Un logo PNG officiel fourni sans SVG doit primer : le CMS préfère le .svg s'il existe.
    case "$f" in
      logo.png|logo-dark.png|logo-icon.png) rm -f "$BRAND/${f%.png}.svg" ;;
    esac
    info "installé : $f"
  else
    alerte "absent dans $SOURCE : $f (le fichier Xibo d'origine reste en place)"
  fi
done
for f in logo.png logo-dark.png logo-icon.png; do
  [ -f "$SOURCE/$f" ] && install -m 644 "$SOURCE/$f" "$BRAND/$f" && rm -f "$BRAND/${f%.png}.svg" && info "installé : $f (SVG d'origine retiré)"
done
chown -R www-data:www-data "$BRAND" 2>/dev/null || chown -R 33:33 "$BRAND"
if grep -q 'Reproduction vectorielle' "$BRAND/logo.svg" 2>/dev/null; then
  info "Logo installé : reproduction vectorielle du kit. Déposer le fichier officiel (logo.png ou logo.svg) puis relancer avec --source si nécessaire."
fi

compose restart cms-memcached cms-web >/dev/null
attendre_cms http://127.0.0.1:8080/login 120 || fatal "Le CMS ne répond plus"

REPONSE=$(curl -s -H "Host: $AFFICHAGE_DOMAINE" -H "X-Forwarded-Proto: https" http://127.0.0.1:8080/about/config)
ATTENDU=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["appName"])' "$SOURCE/config.json")
if [[ "$REPONSE" == *"\"appName\":\"$ATTENDU\""* ]]; then
  ok "Le CMS annonce : $(printf '%s' "$REPONSE" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["appName"], "|", d["productName"], "|", d["logoUrl"])')"
else
  erreur "Le CMS n'annonce pas le nom attendu. Réponse : $REPONSE"; exit 2
fi
LOGO_CMS=$(curl -s -H "Host: $AFFICHAGE_DOMAINE" http://127.0.0.1:8080/brand/logo.svg | sha256sum | cut -c1-16)
LOGO_SRC=$(sha256sum "$BRAND/logo.svg" | cut -c1-16)
[ "$LOGO_CMS" = "$LOGO_SRC" ] && ok "Logo servi par le CMS identique au fichier installé" || alerte "Le logo servi diffère du fichier installé (cache ?)"

palier "6a — Résultat"
echo "Thème appliqué. Étape suivante : 06-identite/creer-comptes.sh, puis verifier-aucune-trace.sh."
