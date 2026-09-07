# Architecture retenue et versions figées — PROXYPHAR Affichage

Document de référence de l'installation `intranet.proxyphar.fr`. Version initiale :
7 septembre 2026.

## Vue d'ensemble

```
Internet ──443/tcp──> Nginx 1.24 (hôte, TLS Let's Encrypt)
                         │ 127.0.0.1:8080
                         ▼
                  cms-web (Xibo CMS 4.5.2, Apache + PHP 8.4)
                    │           │             │
                    ▼           ▼             ▼
                cms-db      cms-xmr       cms-memcached    cms-quickchart
            (MySQL 8.4.11) (XMR 1.3)   (memcached 1.6.45) (QuickChart 1.8.1)
                  réseau Docker interne « affichage_default » 172.28.0.0/24
```

- **VPS** : OVHcloud `vps-322ffb27.vps.ovh.net`, 2 vCores, 4 Go RAM, 80 Go, Gravelines.
  Ubuntu Server 24.04 LTS, fuseau Europe/Paris, locale fr_FR.UTF-8, swap 2 Go.
- **Adresses** : 51.75.251.209 (A) et 2001:41d0:305:2100::a4c4 (AAAA) → `intranet.proxyphar.fr`.
- **Exposition** : seuls 22 (SSH par clé), 80 (redirection + validation ACME) et 443 sont
  ouverts (UFW). La base MySQL, memcached, QuickChart et XMR n'ont **aucun port publié**.
  Le CMS n'est publié que sur `127.0.0.1:8080`, derrière Nginx.
- **Push vers les players (XMR)** : WebSocket `wss://intranet.proxyphar.fr/xmr`, relayé par
  Nginx puis par l'Apache du conteneur vers `cms-xmr:8080`. Le port ZeroMQ 9505 (players v3)
  n'est pas exposé et l'adresse `XMR_PUB_ADDRESS` est vide.
- **Installation** : `/opt/affichage` (fichier `docker-compose.yml`, `config.env` 600, `shared/`
  données, `DOCS/` documentation, `bin/` scripts, `backups/` exports SQL locaux).

## Versions figées

| Composant | Version / tag | Empreinte relevée le 7 septembre 2026 |
|-----------|---------------|----------------------------------------|
| Xibo CMS | `ghcr.io/xibosignage/xibo-cms:release-4.5.2` | `sha256:d34c45b05995d18d9d9799e6cb4ac5e42f0b31f212d88708447418e1a4df6dc2` |
| Xibo XMR | `ghcr.io/xibosignage/xibo-xmr:1.3` | `sha256:92e60111164a1f58538134e119bb025e998127a784800f03c62e6488956cbfd3` |
| MySQL | `mysql:8.4.11` | `sha256:b3b90af2a6552ae30c266fdb7d5dd55f3afb72404bb78d37fe8a23eb857fd3fb` |
| memcached | `memcached:1.6.45-alpine` | `sha256:c29847751abb41f4c268c84fb3087fee05d4edcbda44409ccb5086e26148e8a7` |
| QuickChart | `ianw/quickchart:v1.8.1` | `sha256:12e2d442e2db9974f2b310b72fadd4f6d595d0a0bf5480c3d50ef5cb5967ee56` |
| Nginx | paquet Ubuntu `nginx` 1.24.0 | — |
| Certbot | paquet Ubuntu `certbot` | — |
| Docker Engine | dépôt officiel Docker (version notée à l'installation) | — |

Les empreintes réellement téléchargées sur le VPS sont consignées dans
`/opt/affichage/DOCS/empreintes-images.txt` par le script d'installation ; elles doivent
correspondre à ce tableau. Le fichier compose officiel de `xibo-docker` 4.5.2 référence
ces mêmes images (`mysql:8.4`, `xibo-xmr:1.3`, `xibo-cms:release-4.5.2`) ; seuls les tags
ont été précisés au niveau du correctif.

## Réglages du CMS appliqués

| Réglage | Valeur | Raison |
|---------|--------|--------|
| Langue (`DEFAULT_LANGUAGE`) | `fr` (détection navigateur désactivée) | interface en français |
| Fuseau (`defaultTimezone`) | `Europe/Paris` | planifications à l'heure de Paris |
| Format de date | `d/m/Y H:i` | usage français |
| `XMR_WS_ADDRESS` | `wss://intranet.proxyphar.fr/xmr` | push WebSocket via 443 |
| `XMR_PUB_ADDRESS` | vide | ZeroMQ 9505 non exposé |
| Limite de bibliothèque | 40 Go (`41943040` Ko) | voir ci-dessous |
| Envoi maximal par fichier | 2 Go (PHP et Nginx) | voir ci-dessous |
| Autorisation automatique des écrans | désactivée | tout player est validé à la main |
| Rapport d'usage anonyme (`PHONE_HOME`) | désactivé | pas de télémétrie sortante |
| Force HTTPS / HSTS côté CMS | désactivés | assurés par Nginx (301 + HSTS 1 an) |
| Cookies de session | `Secure`, `HttpOnly`, `SameSite=Lax` | CMS servi en HTTPS uniquement |
| Proxys de confiance | `172.28.0.0/24,127.0.0.1` (`settings-custom.php`) | adresses clientes réelles et détection HTTPS |

## Limite d'envoi et dimensionnement du disque (80 Go)

| Poste | Réservation |
|-------|-------------|
| Système, Docker, images (× 2 pendant une mise à jour), journaux | ~12 Go |
| Base MySQL (`shared/db`) | ~2 Go, croît avec les statistiques de diffusion |
| Bibliothèque de médias (`shared/cms/library`) | **40 Go maximum** (limite appliquée par le CMS) |
| Fichiers temporaires d'envoi (`library/temp`, jusqu'à 2 Go par fichier) | 4 Go |
| Exports SQL locaux (7 jours) et export interne Xibo | ~2 Go |
| Copie de restauration de test (bibliothèque dupliquée temporairement) | doit tenir dans l'espace restant |
| Marge de sécurité | ≥ 15 Go |

La limite par fichier de **2 Go** couvre une vidéo de vitrine en 1080p de plusieurs
minutes ; au-delà, compresser la vidéo avant envoi. La limite de bibliothèque de **40 Go**
laisse la place au test de restauration sur copie tant que la bibliothèque reste sous
20 Go ; au-delà, réaliser le test de restauration sur une autre machine (voir
`03-sauvegarde-restauration.md`). Surveiller `df -h /` : au-dessus de 70 % d'occupation,
prévoir un nettoyage de bibliothèque (Administration > Paramètres > Rangement) ou un
gabarit de disque supérieur.

## Fichiers de configuration

| Fichier | Rôle |
|---------|------|
| `/opt/affichage/docker-compose.yml` | pile Docker, tags figés, ports |
| `/opt/affichage/config.env` (600) | secrets et paramètres du CMS ; comptes en lignes commentées |
| `/opt/affichage/shared/cms/custom/settings-custom.php` | proxys de confiance, nom d'hôte canonique |
| `/opt/affichage/shared/cms/library/brand/` | identité PROXYPHAR (`config.json`, `theme.css`, logos) |
| `/etc/nginx/sites-available/intranet.proxyphar.fr*.conf`, `/etc/nginx/snippets/proxyphar-*.conf` | frontal HTTPS |
| `/etc/letsencrypt/live/intranet.proxyphar.fr/` | certificat (renouvelé par `certbot.timer`) |
| `/opt/affichage/backup.env` (600), `/opt/affichage/bin/affichage-backup.sh` | sauvegarde externe quotidienne |
| `/etc/ssh/sshd_config.d/00-proxyphar.conf` | durcissement SSH |
| `/etc/fail2ban/jail.d/proxyphar.local` | fail2ban |

## Comptes

| Compte | Où | Rôle |
|--------|----|------|
| `proxyadmin` | système (SSH par clé, sudo) | administration du VPS |
| `root` | système (SSH par clé uniquement, secours) | — |
| `admin_proxyphar` | CMS, Super administrateur | administration du CMS |
| `hotline` | CMS, Utilisateur, groupe « Hotline PROXYPHAR » | contenus, planification, écrans |
| `cms` | MySQL (interne au réseau Docker) | base du CMS |
