#!/usr/bin/env bash
# Étape 5 — Nginx en frontal et certificat Let's Encrypt.
#
# - installe Nginx et Certbot (paquets Ubuntu 24.04) ;
# - serveur par défaut qui refuse l'accès par IP nue ou autre nom ;
# - obtient le certificat pour intranet.proxyphar.fr (validation webroot, clé ECDSA) ;
# - active le site HTTPS (HTTP redirigé, HSTS, X-Content-Type-Options, Referrer-Policy) ;
# - installe le crochet de rechargement et vérifie le renouvellement à blanc.
#
# Usage : sudo ./installer-nginx-tls.sh --email ADRESSE [--test]
#   --email  adresse recevant les avis d'expiration Let's Encrypt (boîte de service)
#   --test   utilise l'autorité de test Let's Encrypt (certificat non reconnu), pour
#            répéter l'installation sans consommer les quotas de production

KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/common.sh
. "$KIT_DIR/lib/common.sh"

EMAIL=""; TEST=0
while [ $# -gt 0 ]; do
  case "$1" in
    --email) EMAIL="$2"; shift 2 ;;
    --test) TEST=1; shift ;;
    --aide|-h|--help) sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) fatal "Option inconnue : $1" ;;
  esac
done
[ -n "$EMAIL" ] || fatal "Indiquer --email ADRESSE (avis d'expiration Let's Encrypt)"
exiger_root
export DEBIAN_FRONTEND=noninteractive
NGX="$KIT_DIR/05-nginx-tls/nginx"

palier "5 — Nginx et TLS pour $AFFICHAGE_DOMAINE"

# --- Préalables ---------------------------------------------------------------------
attendre_cms http://127.0.0.1:8080/login 30 || fatal "Le CMS ne répond pas sur 127.0.0.1:8080 : terminer l'étape 4"
command -v dig >/dev/null 2>&1 || apt-get install -y -qq bind9-dnsutils >/dev/null
A_PUBLIC=$(dig +short A "$AFFICHAGE_DOMAINE" @1.1.1.1 | sed -n 1p)
[ "$A_PUBLIC" = "$AFFICHAGE_IPV4" ] || fatal "$AFFICHAGE_DOMAINE ne pointe pas encore vers $AFFICHAGE_IPV4 (vu : '${A_PUBLIC:-aucun}') : terminer l'étape 3"

# --- Nginx --------------------------------------------------------------------------
apt-get install -y -qq nginx certbot >/dev/null
install -d -m 755 /var/www/letsencrypt
cp "$NGX"/snippets/proxyphar-*.conf /etc/nginx/snippets/
cp "$NGX/proxyphar-global.conf" /etc/nginx/conf.d/proxyphar-global.conf
cp "$NGX/00-default-deny.conf" /etc/nginx/sites-available/00-default-deny.conf
cp "$NGX/intranet.proxyphar.fr-http.conf" /etc/nginx/sites-available/intranet.proxyphar.fr-http.conf
cp "$NGX/intranet.proxyphar.fr.conf" /etc/nginx/sites-available/intranet.proxyphar.fr.conf
rm -f /etc/nginx/sites-enabled/default
ln -sf /etc/nginx/sites-available/00-default-deny.conf /etc/nginx/sites-enabled/00-default-deny.conf
ln -sf /etc/nginx/sites-available/intranet.proxyphar.fr-http.conf /etc/nginx/sites-enabled/intranet.proxyphar.fr-http.conf
rm -f /etc/nginx/sites-enabled/intranet.proxyphar.fr.conf   # activé après obtention du certificat
nginx -t 2>&1 | sed 's/^/    /'
systemctl enable --now nginx >/dev/null
systemctl reload nginx
ok "Nginx actif : port 80 (ACME + redirection), accès par IP nue refusé"

# --- Certificat ---------------------------------------------------------------------
OPTIONS_TEST=""
[ "$TEST" -eq 1 ] && OPTIONS_TEST="--test-cert"
if [ -f "/etc/letsencrypt/live/$AFFICHAGE_DOMAINE/fullchain.pem" ]; then
  info "Certificat déjà présent, pas de nouvelle demande"
else
  info "Demande du certificat Let's Encrypt (validation HTTP-01 via /var/www/letsencrypt)"
  # shellcheck disable=SC2086
  certbot certonly --webroot -w /var/www/letsencrypt -d "$AFFICHAGE_DOMAINE" \
    --non-interactive --agree-tos --email "$EMAIL" --no-eff-email --key-type ecdsa $OPTIONS_TEST
fi
[ -f "/etc/letsencrypt/live/$AFFICHAGE_DOMAINE/fullchain.pem" ] || fatal "Certificat absent après certbot"
ok "Certificat obtenu : $(openssl x509 -in "/etc/letsencrypt/live/$AFFICHAGE_DOMAINE/cert.pem" -noout -issuer -enddate | tr '\n' ' ')"

# --- Site HTTPS ---------------------------------------------------------------------
ln -sf /etc/nginx/sites-available/intranet.proxyphar.fr.conf /etc/nginx/sites-enabled/intranet.proxyphar.fr.conf
nginx -t || fatal "Configuration Nginx invalide (site HTTPS)"
systemctl reload nginx
ok "Site HTTPS actif"

# --- Renouvellement automatique -------------------------------------------------------
install -d /etc/letsencrypt/renewal-hooks/deploy
cat > /etc/letsencrypt/renewal-hooks/deploy/reload-nginx.sh <<'HOOK'
#!/bin/sh
# Recharge Nginx après renouvellement du certificat (crochet Certbot).
systemctl reload nginx
HOOK
chmod +x /etc/letsencrypt/renewal-hooks/deploy/reload-nginx.sh
systemctl enable --now certbot.timer >/dev/null
if certbot renew --dry-run >/tmp/certbot-dry-run.log 2>&1; then
  ok "certbot renew --dry-run : succès (minuterie certbot.timer active)"
else
  erreur "certbot renew --dry-run a échoué :"; tail -20 /tmp/certbot-dry-run.log; exit 2
fi

palier "5 — Résultat"
cat <<FIN
Nginx relaie https://$AFFICHAGE_DOMAINE vers le CMS. Vérification complète :
    sudo $KIT_DIR/05-nginx-tls/verifier-tls.sh
Puis test externe : https://www.ssllabs.com/ssltest/analyze.html?d=$AFFICHAGE_DOMAINE (note A attendue).
Étape suivante : 06-identite.
FIN
