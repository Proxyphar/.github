# Étape 3 — DNS `intranet.proxyphar.fr`

> **Action sur la zone DNS de production `proxyphar.fr`.** Elle n'affecte que le
> sous-domaine `intranet`, qui n'existe pas aujourd'hui (vérifié le 7 septembre 2026 :
> aucun enregistrement A ni AAAA). Elle n'est faite qu'après validation explicite.

## Avant de créer les enregistrements

Sur le VPS, vérifier la connectivité IPv6 (le script le fait) :

```bash
sudo /opt/affichage-kit/03-dns/verifier-dns.sh --avant
```

- Si l'IPv6 répond : créer **A et AAAA**.
- Si l'IPv6 ne répond pas : créer **A seulement**, et ajouter l'AAAA plus tard, une fois
  l'IPv6 configurée (guide OVHcloud « Configurer une IPv6 sur un VPS »). Un AAAA sans
  IPv6 fonctionnelle ferait échouer la validation Let's Encrypt (qui privilégie l'IPv6)
  et l'accès des postes en IPv6.

## Enregistrements à créer (manager OVHcloud)

**Web Cloud** > **Noms de domaine** > `proxyphar.fr` > onglet **Zone DNS** >
**Ajouter une entrée**.

| Type | Sous-domaine | Cible | TTL |
|------|--------------|-------|-----|
| A | `intranet` | `51.75.251.209` | par défaut |
| AAAA | `intranet` | `2001:41d0:305:2100::a4c4` | par défaut (si IPv6 validée) |

Ne pas créer de `www.intranet`, ni de CNAME.

## Vérifier la propagation

Attendre quelques minutes, puis sur le VPS :

```bash
sudo /opt/affichage-kit/03-dns/verifier-dns.sh
```

Le script interroge les serveurs OVH faisant autorité et trois résolveurs publics. Ne
passer à l'étape 4 que lorsque tous répondent avec les bonnes adresses : la demande
de certificat (étape 5) échouerait sinon.

## Facultatif

Le reverse DNS du VPS (manager > VPS > IP > modifier le reverse) peut être positionné à
`intranet.proxyphar.fr`. Sans effet sur le CMS ; utile uniquement si le serveur envoie
des e-mails d'alerte.
