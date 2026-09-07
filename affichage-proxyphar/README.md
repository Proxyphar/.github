# Kit de déploiement PROXYPHAR Affichage

Ce dossier contient tout ce qui est nécessaire pour déployer, sur le VPS OVH
`vps-322ffb27.vps.ovh.net`, un CMS Xibo neuf aux couleurs de PROXYPHAR, joignable
sur `https://intranet.proxyphar.fr`.

Il est conçu pour être exécuté **étape par étape**, avec un compte rendu à chaque
palier. Chaque script affiche en fin d'exécution un bloc `PALIER` à recopier dans le
compte rendu. Aucun script n'enchaîne l'étape suivante de lui-même.

## Versions figées

| Composant | Version | Source |
|-----------|---------|--------|
| Système | Ubuntu Server 24.04 LTS | image OVHcloud |
| Xibo CMS | 4.5.2 (`ghcr.io/xibosignage/xibo-cms:release-4.5.2`) | dernière version stable 4.x au 7 septembre 2026 |
| Xibo XMR | 1.3 (`ghcr.io/xibosignage/xibo-xmr:1.3`) | version référencée par `xibo-docker` 4.5.2 |
| MySQL | 8.4.11 (`mysql:8.4.11`) | branche 8.4 imposée par `xibo-docker` 4.5.2 |
| memcached | 1.6.45 (`memcached:1.6.45-alpine`) | |
| QuickChart | 1.8.1 (`ianw/quickchart:v1.8.1`) | |
| Nginx | 1.24 (paquet Ubuntu 24.04) | |
| Certbot | paquet Ubuntu 24.04 | Let's Encrypt |

Les empreintes (`sha256`) relevées le 7 septembre 2026 sont dans
`09-docs/01-architecture-et-versions.md`.

## Ordre d'exécution

| Étape | Dossier | Qui | Action destructive ? |
|-------|---------|-----|----------------------|
| 0 | `00-prerequis/` | Alexandre (manager OVH) | **Oui** : réinstallation du VPS |
| 1 | `01-post-install/` | technicien, sur le VPS | non |
| 2 | `02-durcissement/` | technicien, sur le VPS | non (mais coupe l'accès par mot de passe) |
| 3 | `03-dns/` | Alexandre (manager OVH), puis vérification sur le VPS | **Oui** : modification de la zone DNS |
| 4 | `04-cms/` | technicien, sur le VPS | non |
| 5 | `05-nginx-tls/` | technicien, sur le VPS | non |
| 6 | `06-identite/` | technicien, sur le VPS | non |
| 7 | `07-sauvegarde/` | technicien, sur le VPS + destination externe | non |
| 8 | `08-recette/` | technicien + Alexandre | non |
| 9 | `09-docs/` | copié dans `/opt/affichage/DOCS/` par l'étape 4 | non |

Les deux actions destructives (réinstallation, DNS) ne sont **jamais** exécutées par
un script : elles se font dans le manager OVH après validation explicite.

## Mise en place du kit sur le VPS

Depuis le poste d'administration, une fois l'étape 0 terminée :

```bash
scp -r affichage-proxyphar ubuntu@51.75.251.209:/tmp/
ssh ubuntu@51.75.251.209
sudo -i
mv /tmp/affichage-proxyphar /opt/affichage-kit
chmod +x /opt/affichage-kit/*/*.sh
```

Après l'étape 2, la connexion se fait avec l'utilisateur `proxyadmin`.

Chaque script accepte `--aide` et décrit ce qu'il va faire avant d'agir.

## Guide d'exécution

`GUIDE-EXECUTION.md` détaille chaque étape, commande par commande, avec ce qu'il faut
vérifier et transmettre à chaque palier. C'est le document à suivre pour dérouler le kit.

## Visuels

`06-identite/brand/` contient une reproduction vectorielle du logo PROXYPHAR aux couleurs
officielles, violet `#6B2D90` et rose `#E6007E`. Les bitmaps `favicon.ico`, `192x192.png`
et `512x512.png` sont générés sur le VPS par `generer-placeholders.py`. Un fichier officiel
déposé dans ce dossier, `logo.png` ou `logo.svg`, est pris en compte par `appliquer-theme.sh`.

## Ce que le kit ne fait pas

- Il ne stocke aucun mot de passe : ils sont générés sur le VPS, écrits dans
  `/opt/affichage/config.env` (droits 600) et affichés une seule fois en fin d'installation.
- Il ne modifie ni le manager OVH ni la zone DNS.
- Il ne remplace pas la recette humaine : l'enrôlement d'un player réel et la note SSL
  Labs sont à réaliser par une personne (procédures dans `08-recette/`).

## Contact

Kit préparé pour le service client PROXYPHAR (Alexandre Akkari).
Journal d'exécution des scripts : `/var/log/affichage-kit.log`.
