#!/usr/bin/env bash
# Étape 3 — Vérification de la connectivité IPv6 du VPS et de la propagation DNS.
#
# Usage : sudo ./verifier-dns.sh [--avant]
#   --avant : ne vérifie que la connectivité (avant création des enregistrements)
#
# Sans option : vérifie que intranet.proxyphar.fr pointe vers les adresses attendues
# depuis les serveurs faisant autorité et depuis des résolveurs publics.

KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/common.sh
. "$KIT_DIR/lib/common.sh"

AVANT=0
for arg in "$@"; do
  case "$arg" in
    --avant) AVANT=1 ;;
    --aide|-h|--help) sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) fatal "Option inconnue : $arg" ;;
  esac
done
exiger_root
command -v dig >/dev/null 2>&1 || { apt-get install -y -qq bind9-dnsutils >/dev/null; }
ECARTS=0

palier "3 — Connectivité du VPS"
IP4_PUB=$(curl -4 -s -m 10 https://api.ipify.org || true)
IP6_PUB=$(curl -6 -s -m 10 https://api64.ipify.org || true)
if [ "$IP4_PUB" = "$AFFICHAGE_IPV4" ]; then ok "IPv4 publique : $IP4_PUB"; else
  erreur "IPv4 publique vue de l'extérieur : '${IP4_PUB:-aucune}' (attendu $AFFICHAGE_IPV4)"; ECARTS=$((ECARTS + 1)); fi
if [ -n "$IP6_PUB" ]; then
  if [ "$IP6_PUB" = "$AFFICHAGE_IPV6" ]; then ok "IPv6 publique : $IP6_PUB — l'enregistrement AAAA peut être créé"; else
    alerte "IPv6 publique '$IP6_PUB' différente de l'inventaire ($AFFICHAGE_IPV6) : signaler l'écart avant de créer l'AAAA"; ECARTS=$((ECARTS + 1)); fi
else
  alerte "Pas de connectivité IPv6 sortante : créer uniquement l'enregistrement A pour l'instant"
  IPV6_ABSENTE=1
fi
[ "$AVANT" -eq 1 ] && { palier "3 — Résultat (avant DNS) : $ECARTS écart(s)"; exit 0; }

palier "3 — Propagation DNS de $AFFICHAGE_DOMAINE"
NS_LIST=$(dig +short NS proxyphar.fr | sed 's/\.$//')
[ -n "$NS_LIST" ] || { erreur "Impossible d'obtenir les serveurs NS de proxyphar.fr"; exit 2; }
info "Serveurs faisant autorité : $(echo "$NS_LIST" | tr '\n' ' ')"
verifier_resolveur() {
  local resolveur="$1" a aaaa complement
  a=$(dig +short +time=5 +tries=1 A "$AFFICHAGE_DOMAINE" "@$resolveur" | grep -E '^[0-9.]+$' | tr '\n' ' ' | sed 's/ $//')
  aaaa=$(dig +short +time=5 +tries=1 AAAA "$AFFICHAGE_DOMAINE" "@$resolveur" | grep -E ':' | tr '\n' ' ' | sed 's/ $//')
  if [ "$a" = "$AFFICHAGE_IPV4" ]; then ok "$resolveur : A = $a"; else
    erreur "$resolveur : A = '${a:-aucun}' (attendu $AFFICHAGE_IPV4)"; ECARTS=$((ECARTS + 1)); fi
  if [ -n "$aaaa" ]; then
    if [ "$aaaa" = "$AFFICHAGE_IPV6" ] && [ -z "${IPV6_ABSENTE:-}" ]; then ok "$resolveur : AAAA = $aaaa"; else
      complement=""
      [ -n "${IPV6_ABSENTE:-}" ] && complement=" (et l'IPv6 du VPS ne répond pas)"
      erreur "$resolveur : AAAA = '$aaaa' alors que l'IPv6 attendue est ${AFFICHAGE_IPV6}${complement}"; ECARTS=$((ECARTS + 1)); fi
  else
    if [ -n "${IPV6_ABSENTE:-}" ]; then info "$resolveur : pas d'AAAA (cohérent : IPv6 non active sur le VPS)"; else
      alerte "$resolveur : pas d'AAAA (attendu $AFFICHAGE_IPV6)"; ECARTS=$((ECARTS + 1)); fi
  fi
}
for ns in $NS_LIST; do verifier_resolveur "$ns"; done
for r in 1.1.1.1 8.8.8.8 9.9.9.9; do verifier_resolveur "$r"; done

palier "3 — Résultat : $ECARTS écart(s)"
if [ "$ECARTS" -eq 0 ]; then ok "DNS propagé. Passer à l'étape 4 (04-cms/installer-cms.sh)."; else
  alerte "Attendre la propagation ou corriger la zone, puis relancer ce script."; exit 2; fi
