#!/usr/bin/env bash
# Étape 5 (contrôle) — Vérifie le frontal HTTPS depuis le VPS.
#
# Contrôles : redirection HTTP→HTTPS, page de connexion en HTTPS, en-têtes de sécurité,
# refus de l'IP nue et du nom OVH, versions TLS, certificat, WebSocket XMR, renouvellement.
#
# Usage : sudo ./verifier-tls.sh

KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/common.sh
. "$KIT_DIR/lib/common.sh"
case "${1:-}" in --aide|-h|--help) sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;; esac
ECARTS=0
verif() { if eval "$2"; then ok "$1"; else erreur "$1"; ECARTS=$((ECARTS + 1)); fi; }

palier "5 — Contrôle HTTPS de $AFFICHAGE_DOMAINE"
D="$AFFICHAGE_DOMAINE"

verif "HTTP redirigé vers HTTPS (301)" \
  "[ \"\$(curl -s -o /dev/null -w '%{http_code} %{redirect_url}' http://$D/)\" = \"301 https://$D/\" ]"
verif "Page de connexion servie en HTTPS (200)" \
  "[ \"\$(curl -s -o /dev/null -w '%{http_code}' https://$D/login)\" = 200 ]"
# shellcheck disable=SC2034  # ENTETES est lue dans les expressions évaluées par verif()
ENTETES=$(curl -s -I https://$D/login)
verif "En-tête HSTS présent (max-age >= 1 an)" "printf '%s' \"\$ENTETES\" | grep -qi 'strict-transport-security: max-age=31536000'"
verif "En-tête X-Content-Type-Options: nosniff (une seule fois)" "[ \"\$(printf '%s' \"\$ENTETES\" | grep -ci 'x-content-type-options')\" = 1 ]"
verif "En-tête Referrer-Policy présent" "printf '%s' \"\$ENTETES\" | grep -qi 'referrer-policy:'"
verif "Aucune version de serveur divulguée" "! printf '%s' \"\$ENTETES\" | grep -qiE '^server: (nginx|apache)/[0-9]'"
verif "IP nue en HTTP : connexion fermée sans réponse (444)" \
  "curl -s -o /dev/null -m 10 http://$AFFICHAGE_IPV4/ ; rc=\$? ; [ \$rc -eq 52 ] || [ \$rc -eq 56 ]"
verif "IP nue en HTTPS : négociation TLS refusée" \
  "! curl -sk -o /dev/null -m 10 https://$AFFICHAGE_IPV4/ 2>/dev/null"
verif "Nom OVH (vps-322ffb27.vps.ovh.net) en HTTPS : refusé" \
  "! curl -sk -o /dev/null -m 10 https://vps-322ffb27.vps.ovh.net/ 2>/dev/null"
verif "TLS 1.1 refusé" "! openssl s_client -connect $D:443 -servername $D -tls1_1 </dev/null >/dev/null 2>&1"
verif "TLS 1.3 accepté" "openssl s_client -connect $D:443 -servername $D -tls1_3 </dev/null 2>/dev/null | grep -q 'Protocol *: TLSv1.3'"
verif "Certificat émis par Let's Encrypt et valide plus de 20 jours" \
  "openssl s_client -connect $D:443 -servername $D </dev/null 2>/dev/null | openssl x509 -noout -issuer -checkend 1728000 | grep -q \"Let's Encrypt\""
verif "WebSocket XMR (/xmr) : bascule de protocole (101)" \
  "[ \"\$(curl -s -o /dev/null -w '%{http_code}' --http1.1 -m 10 -H 'Connection: Upgrade' -H 'Upgrade: websocket' -H 'Sec-WebSocket-Version: 13' -H \"Sec-WebSocket-Key: \$(openssl rand -base64 16)\" https://$D/xmr)\" = 101 ]"
verif "Renouvellement automatique : minuterie certbot.timer active" "systemctl is-active --quiet certbot.timer"
verif "Renouvellement à blanc (certbot renew --dry-run)" "certbot renew --dry-run >/dev/null 2>&1"
verif "Le CMS voit les requêtes en HTTPS (pas de boucle de redirection)" \
  "[ \"\$(curl -s -o /dev/null -w '%{num_redirects}' -L --max-redirs 3 https://$D/)\" -le 2 ]"

palier "5 — Résultat : $ECARTS écart(s)"
info "Test externe à réaliser depuis un poste : https://www.ssllabs.com/ssltest/analyze.html?d=$D (note A attendue)"
[ "$ECARTS" -eq 0 ] || exit 2
