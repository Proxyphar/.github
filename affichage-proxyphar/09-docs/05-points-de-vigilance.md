# Points de vigilance et limites connues

## Sécurité et accès

- **Une seule clé SSH** ouvre le VPS (`proxyadmin` et `root` par clé). Sa perte impose
  un passage par le mode rescue OVH ou une réinstallation : conserver une copie chiffrée
  au coffre du service.
- Le compte `root` reste joignable **par clé** (`PermitRootLogin prohibit-password`),
  conformément à la demande initiale. Pour le fermer complètement, passer à
  `PermitRootLogin no` dans `/etc/ssh/sshd_config.d/00-proxyphar.conf`.
- **Clé CMS** : toute personne qui la connaît peut présenter un player au CMS. Elle ne
  donne pas accès au contenu tant que l'écran n'est pas autorisé à la main ; ne jamais
  activer l'autorisation automatique. La changer (Administration > Paramètres) si elle
  a été divulguée : les players déjà autorisés ne sont pas affectés.
- Le CMS limite les tentatives de connexion à 5 par 15 minutes **et par adresse IP** ;
  les officines derrière une même adresse partagée peuvent se bloquer mutuellement en
  cas d'erreurs répétées.
- **2FA** : à activer sur `admin_proxyphar` dès que le relais SMTP est configuré, ou avec
  une application d'authentification (sans SMTP).
- Aucun envoi d'e-mail tant que `CMS_SMTP_*` n'est pas complété dans `config.env` :
  pas de rappel de mot de passe, pas d'alerte de maintenance, pas de 2FA par e-mail.
  L'envoi passe par la messagerie Google de PROXYPHAR avec un mot de passe d'application ;
  si ce mot de passe est révoqué côté Google, les envois s'arrêtent sans alerte.

## Infrastructure

- **4 Go de RAM** : MySQL (1 Go), CMS (1 Go), XMR (256 Mo), Nginx et système. Le test de
  restauration sur copie double temporairement l'occupation : hors exploitation.
- **80 Go de disque** : bibliothèque plafonnée à 40 Go, envois à 2 Go par fichier
  (`01-architecture-et-versions.md`). Surveiller `df -h /`.
- **IPv6** : l'enregistrement AAAA n'a de sens que si l'IPv6 du VPS répond. Un AAAA
  avec une IPv6 inactive fait échouer le renouvellement Let's Encrypt et l'accès des
  clients en IPv6. Vérification : `03-dns/verifier-dns.sh`.
- **Docker et UFW** : Docker gère ses propres règles réseau ; un port publié sur
  `0.0.0.0` contournerait UFW. Toute modification de `docker-compose.yml` doit conserver
  les publications sur `127.0.0.1` uniquement, et aucune pour `cms-db` et `cms-xmr`.
- Le sous-réseau Docker `172.28.0.0/24` est fixe : il doit rester cohérent avec
  `settings-custom.php` (proxys de confiance), sinon le CMS ne verra plus les requêtes
  comme HTTPS ni les adresses IP réelles.

## Fonctionnel

- **Players 3.x non pris en charge** : le port ZeroMQ 9505 n'est pas exposé. Pour les
  accepter malgré tout : publier `9505:9505` sur `cms-xmr`, ouvrir `ufw allow 9505/tcp`,
  renseigner `XMR_PUB_ADDRESS` = `tcp://intranet.proxyphar.fr:9505`. Non recommandé.
- **Licences players** : les players Android, webOS et Tizen nécessitent une licence
  Xibo par écran ; le player Windows est gratuit. À prévoir dans l'offre aux officines.
- **Identité** : les logos du kit sont une reproduction vectorielle du logo PROXYPHAR,
  aux couleurs officielles. Le fichier officiel, s'il est fourni en PNG ou SVG, se dépose
  dans `06-identite/brand/` puis `06-identite/appliquer-theme.sh` est relancé. Le texte de licence AGPL reste
  affiché sur la page de connexion (`removeLicenceFromLogin: false`) : Xibo est un
  logiciel libre et cette mention fait partie de ses conditions d'utilisation.
- **Xibo 4.5** a une nouvelle interface (React). Les anciens thèmes `web/theme/custom`
  ne sont plus pris en charge : l'identité passe uniquement par `library/brand/`.
- **Widgets externes** (météo, flux RSS, pages web) : le CMS doit pouvoir sortir sur
  Internet (UFW autorise le trafic sortant). Les pages web affichées par les players
  sont chargées par les players eux-mêmes, depuis le réseau de l'officine.
- **Statistiques de diffusion** : leur collecte fait grossir la base ; si elles ne sont
  pas exploitées, les désactiver dans les profils d'écrans.

## Exploitation

- **Sauvegarde externe** : la destination (`BACKUP_REMOTE`) doit être créée et
  renseignée ; tant qu'elle est vide, seul l'export SQL local existe et la sauvegarde
  n'est **pas conforme**. Contrôler `DERNIER-ETAT` chaque semaine ; tester une
  restauration chaque mois.
- **Backup automatisé OVH** : à vérifier dans le manager ; il n'est pas pilotable
  depuis le VPS. Les images antérieures à la réinstallation (ancienne instance) restent
  disponibles jusqu'à leur rotation.
- **Redémarrages** : les mises à jour du noyau attendent un redémarrage manuel
  (`/var/run/reboot-required`). Prévoir une fenêtre mensuelle.
- **Journaux** : Nginx dans `/var/log/nginx/affichage.*.log`, conteneurs via
  `docker compose logs`, kit dans `/var/log/affichage-kit.log`, sauvegardes dans
  `/var/log/affichage-backup.log`. Les journaux du CMS sont dans Administration > Journal.
- **Support Xibo** : projet communautaire ; pas de support éditeur sans contrat. La
  communauté (community.xibo.org.uk) et la documentation (xibosignage.com/docs) sont
  en anglais.
