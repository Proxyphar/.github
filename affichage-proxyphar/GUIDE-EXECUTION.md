# Guide d'exécution pas à pas — PROXYPHAR Affichage

Ce guide est destiné à la personne qui déroule le kit : Alexandre, depuis son poste
Windows, avec le compte OVHcloud de PROXYPHAR et le compte GitHub TechniqueProxyphar.

Décisions acquises le 7 septembre 2026 :

| Point | Décision |
|-------|----------|
| Réinstallation du VPS | validée, l'instance « bubu.re » est effacée |
| Enregistrements DNS `intranet` | validés |
| Exécution du kit | Alexandre, avec ce guide |
| Identité et messagerie | logo PROXYPHAR, messagerie Google des boîtes actuelles |
| Sauvegarde externe | Object Storage OVHcloud, région GRA |

Règles pendant toute l'exécution :

- **Un palier à la fois.** Chaque script se termine par un bloc `PALIER`. Copiez-le et
  transmettez-le-moi avant de passer à l'étape suivante ; j'analyse et je donne le feu vert.
- **Aucun mot de passe dans nos échanges.** Les identifiants générés vont dans le coffre
  de mots de passe du service, jamais dans le chat, jamais dans un e-mail.
- **Rien n'est irréversible sauf l'étape 0d**, déjà validée. En cas de doute sur un
  résultat, arrêtez-vous et envoyez-moi la sortie complète de la commande.

Durée totale estimée : une demi-journée, hors délais d'attente OVH et DNS.

---

## Étape 0a — Clé SSH sur votre poste (10 min)

Où : votre poste Windows, dans **PowerShell**.

1. Vérifiez que le client OpenSSH est présent :

   ```powershell
   ssh -V
   ```

   Si la commande est inconnue : Paramètres Windows, Applications, Fonctionnalités
   facultatives, ajouter « Client OpenSSH », puis rouvrir PowerShell.

2. Générez la paire de clés, en choisissant une phrase de passe que vous rangez au coffre :

   ```powershell
   ssh-keygen -t ed25519 -a 100 -C "proxyphar-affichage-admin" -f "$env:USERPROFILE\.ssh\proxyphar-affichage"
   ```

3. Affichez la clé publique et copiez la ligne entière :

   ```powershell
   Get-Content "$env:USERPROFILE\.ssh\proxyphar-affichage.pub"
   ```

4. Gardez cette ligne sous la main : elle sera collée directement dans le formulaire de
   réinstallation du VPS, étape 0d, champ « Votre clé SSH Publique ». Il n'est pas
   nécessaire de l'enregistrer au préalable dans l'espace client. Si vous préférez la
   stocker : votre nom en haut à droite, **Mes offres & services**, section
   **Mes services**, **Clés SSH**, **Ajouter une clé SSH**, type **Dédié**, puis la ligne.

5. Créez le fichier `$env:USERPROFILE\.ssh\config` avec le Bloc-notes, contenu :

   ```
   Host affichage
       HostName 51.75.251.209
       User ubuntu
       IdentityFile ~/.ssh/proxyphar-affichage
       IdentitiesOnly yes
   ```

   Après l'étape 2, remplacez `User ubuntu` par `User proxyadmin`.

À me transmettre : « clé générée », rien d'autre. La clé privée reste sur votre poste.

## Étape 0b — Object Storage GRA (15 min)

Où : manager OVHcloud, **Public Cloud**.

Suivez `07-sauvegarde/object-storage-ovh.md`, sections 1 et 2 : conteneur
`proxyphar-affichage-sauvegardes` en région GRA, utilisateur `affichage-sauvegarde` avec
le seul rôle ObjectStore operator, identifiants S3 générés et rangés au coffre.

À me transmettre : le nom du conteneur et l'endpoint S3 affiché, sans les clés.

## Étape 0c — Mot de passe d'application Google (10 min)

Où : le compte Google de la boîte qui enverra les e-mails du CMS, par exemple
`affichage@proxyphar.com` ou la boîte technique. Une boîte dédiée est préférable.

1. Connectez-vous à ce compte sur https://myaccount.google.com, rubrique **Sécurité**.
2. Activez la **validation en deux étapes** si elle ne l'est pas.
3. Rubrique **Mots de passe des applications** : créez-en un nommé
   `PROXYPHAR Affichage`. Google affiche 16 caractères, une seule fois : rangez-les au coffre.

Si l'administrateur Google Workspace interdit les mots de passe d'application, la
solution de repli est le relais SMTP Google (`smtp-relay.gmail.com`) autorisé pour
l'adresse IP 51.75.251.209 dans la console d'administration ; dites-le-moi, j'adapterai
`config.env`.

À me transmettre : l'adresse de la boîte expéditrice.

## Étape 0d — Réinstallation du VPS (20 min, action irréversible validée)

Où : manager OVHcloud, **Bare Metal Cloud**, **Serveurs privés virtuels**.

1. Sélectionnez `vps-322ffb27.vps.ovh.net`. Dans l'onglet **Accueil**, bloc
   **OS / Distribution**, cliquez sur le bouton `...` puis **Réinstaller mon VPS**.
2. Système : **Ubuntu 24.04**, sans image applicative.
3. Champ **Votre clé SSH Publique** : collez la ligne de la clé publique de l'étape 0a,
   sur une seule ligne. Si vous l'aviez stockée dans l'espace client, choisissez-la dans
   **Clé SSH à pré-installer**.
4. Cochez **Je ne souhaite pas recevoir par e-mail les codes d'authentification de mon
   VPS** : l'accès se fera par clé uniquement, aucun mot de passe temporaire ne circulera.
5. Confirmez. OVH avertit que tous les disques seront formatés : c'est l'effet attendu.
   Attendez l'e-mail de fin de réinstallation ; l'utilisateur de connexion est `ubuntu`.

Puis, dans PowerShell, oubliez l'ancienne empreinte du serveur et connectez-vous :

```powershell
ssh-keygen -R 51.75.251.209
ssh-keygen -R vps-322ffb27.vps.ovh.net
ssh affichage
```

Répondez `yes` à la question sur l'empreinte du nouveau serveur. Vous devez obtenir une
invite `ubuntu@vps-322ffb27:~$`. Tapez `exit`.

À me transmettre : l'heure de fin de réinstallation et « connexion ubuntu OK ».

## Étape 0e — Copier le kit sur le VPS (10 min)

Où : votre poste, puis le VPS.

1. Récupérez le kit depuis GitHub, dépôt `Proxyphar/Intranet`, branche
   `claude/affichage-proxyphar-deployment-x04re2` : bouton **Code**, **Download ZIP**.
   Décompressez l'archive ; le dossier utile est `affichage-proxyphar`.

2. Copiez-le sur le VPS, en adaptant le chemin de votre dossier de téléchargement :

   ```powershell
   scp -r "$env:USERPROFILE\Downloads\Intranet-claude-affichage-proxyphar-deployment-x04re2\affichage-proxyphar" affichage:/tmp/
   ssh affichage
   ```

3. Sur le VPS :

   ```bash
   sudo -i
   mv /tmp/affichage-proxyphar /opt/affichage-kit
   find /opt/affichage-kit -type f \( -name '*.sh' -o -name '*.md' -o -name '*.conf' -o -name '*.template' -o -name '*.yml' -o -name '*.py' -o -name '*.php' -o -name '*.json' -o -name '*.css' -o -name '*.svg' -o -name '*.service' -o -name '*.timer' \) -exec sed -i 's/\r$//' {} +
   chmod +x /opt/affichage-kit/*/*.sh
   ls /opt/affichage-kit
   ```

   La commande `find` retire d'éventuelles fins de ligne Windows ajoutées lors de la
   copie. Vous devez voir les dossiers `00-prerequis` à `09-docs`, `lib`, et les
   fichiers `README.md` et `GUIDE-EXECUTION.md`.

À me transmettre : la sortie de `ls /opt/affichage-kit`.

## Étape 1 — Vérification du système (10 min)

Où : le VPS, en root (`sudo -i`).

```bash
/opt/affichage-kit/01-post-install/verifier-systeme.sh --corriger
```

Le script vérifie Ubuntu 24.04, le disque, la mémoire, crée le swap, règle le fuseau
Europe/Paris, la locale fr_FR et l'heure NTP, puis met les paquets à jour. S'il indique
qu'un redémarrage est requis :

```bash
reboot
```

Attendez deux minutes, reconnectez-vous avec `ssh affichage`, `sudo -i`, et relancez le
script sans option pour confirmer « 0 écart ».

À me transmettre : le bloc `PALIER 1` final.

## Étape 2 — Durcissement (15 min)

Où : le VPS, en root.

```bash
/opt/affichage-kit/02-durcissement/durcir.sh
```

Le script crée `proxyadmin` avec votre clé, durcit SSH, active le pare-feu sur 22, 80 et
443, fail2ban et les mises à jour de sécurité automatiques. **Ne fermez pas cette
session.** Ouvrez une seconde fenêtre PowerShell :

```powershell
ssh -i "$env:USERPROFILE\.ssh\proxyphar-affichage" proxyadmin@51.75.251.209
sudo -i
```

Si l'invite root apparaît, tout est bon. Dans cette nouvelle session, verrouillez le
compte fourni par OVH :

```bash
/opt/affichage-kit/02-durcissement/durcir.sh --verrouiller-utilisateur ubuntu
```

Modifiez ensuite `User ubuntu` en `User proxyadmin` dans votre fichier `.ssh\config`.
Toutes les connexions suivantes se font avec `ssh affichage` puis `sudo -i`.

À me transmettre : le bloc `PALIER 2` et « connexion proxyadmin OK, ubuntu verrouillé ».

## Étape 3 — DNS (15 min plus propagation)

Où : le VPS, puis le manager OVHcloud.

1. Sur le VPS :

   ```bash
   /opt/affichage-kit/03-dns/verifier-dns.sh --avant
   ```

   Le script indique si l'IPv6 du VPS répond. Retenez la conclusion : « A et AAAA » ou
   « A seulement ».

2. Manager OVHcloud, **Web Cloud**, **Noms de domaine**, `proxyphar.fr`, onglet
   **Zone DNS**, **Ajouter une entrée** :

   | Type | Sous-domaine | Cible |
   |------|--------------|-------|
   | A | `intranet` | `51.75.251.209` |
   | AAAA | `intranet` | `2001:41d0:305:2100::a4c4`, seulement si le script a validé l'IPv6 |

3. Attendez cinq minutes, puis sur le VPS :

   ```bash
   /opt/affichage-kit/03-dns/verifier-dns.sh
   ```

   Relancez toutes les dix minutes jusqu'à « 0 écart ». Au-delà d'une heure, envoyez-moi
   la sortie.

À me transmettre : le bloc `PALIER 3` à 0 écart.

## Étape 4 — Installation du CMS (20 à 30 min)

Où : le VPS, en root.

```bash
/opt/affichage-kit/04-cms/installer-cms.sh
```

Le script installe Docker, crée `/opt/affichage`, génère `config.env` avec des mots de
passe distincts, télécharge les images figées, démarre la pile, attend le CMS, applique
les réglages PROXYPHAR et vérifie la connexion administrateur. Le téléchargement des
images prend plusieurs minutes.

En fin de script, un bloc affiche **une seule fois** le mot de passe de la base, le
compte administrateur `admin_proxyphar` avec son mot de passe, et la clé CMS. Rangez ces
trois éléments au coffre, puis fermez le terminal.

À me transmettre : le bloc `PALIER 4` **sans les lignes d'identifiants**, c'est-à-dire
l'état des conteneurs uniquement.

## Étape 5 — HTTPS (15 min)

Où : le VPS, en root, puis votre navigateur.

```bash
/opt/affichage-kit/05-nginx-tls/installer-nginx-tls.sh --email ADRESSE_DE_SERVICE
/opt/affichage-kit/05-nginx-tls/verifier-tls.sh
```

Remplacez `ADRESSE_DE_SERVICE` par une boîte qui recevra les avis d'expiration du
certificat, par exemple la boîte technique. Le second script doit conclure « 0 écart ».

Depuis votre poste, ouvrez https://intranet.proxyphar.fr : la page de connexion doit
s'afficher avec un cadenas valide. Lancez ensuite le test externe
https://www.ssllabs.com/ssltest/analyze.html?d=intranet.proxyphar.fr, qui dure deux à
trois minutes.

À me transmettre : le bloc `PALIER 5` du script de vérification et une capture de la
note SSL Labs, A attendue.

## Étape 6 — Identité et comptes (20 min)

Où : le VPS, en root, puis le navigateur.

### 6a. Logo et couleurs

Le kit contient une reproduction vectorielle du logo aux couleurs officielles. Si vous
disposez du fichier officiel, copiez-le d'abord depuis votre poste, en PNG ou SVG :

```powershell
scp "C:\chemin\vers\logo-proxyphar.png" affichage:/tmp/logo.png
```

puis sur le VPS : `mv /tmp/logo.png /opt/affichage-kit/06-identite/brand/logo.png`.
Dans tous les cas :

```bash
/opt/affichage-kit/06-identite/appliquer-theme.sh
```

Rechargez https://intranet.proxyphar.fr/login : le logo, le nom « PROXYPHAR Affichage »
et l'icône d'onglet doivent être en place.

### 6b. Comptes

```bash
/opt/affichage-kit/06-identite/creer-comptes.sh
```

Le script vérifie l'administrateur, crée le groupe « Hotline PROXYPHAR » aux droits
limités, l'utilisateur `hotline` et le partage du dossier racine, puis teste les deux
connexions. Il affiche une seule fois le mot de passe initial de `hotline`, à changer à
sa première connexion : rangez-le au coffre.

### 6c. Messagerie Google

Sur le VPS, éditez le fichier des paramètres :

```bash
nano /opt/affichage/config.env
```

Renseignez `CMS_SMTP_USERNAME` avec la boîte expéditrice, `CMS_SMTP_PASSWORD` avec le
mot de passe d'application de l'étape 0c, `CMS_SMTP_FROM` avec la même boîte. Enregistrez
avec Ctrl+O, Entrée, puis Ctrl+X. Appliquez et testez :

```bash
cd /opt/affichage && docker compose up -d
printf 'Subject: Test PROXYPHAR Affichage\n\nEnvoi de test depuis le CMS.\n' | docker compose exec -T cms-web sendmail VOTRE_ADRESSE
```

Vous devez recevoir l'e-mail dans la minute. Sinon, envoyez-moi la sortie de
`docker compose logs --tail=30 cms-web`.

### 6d. Dans le navigateur, connecté en `admin_proxyphar`

- Profil, en haut à droite : renseignez votre adresse e-mail, puis activez
  l'authentification à deux facteurs, par application ou par e-mail.
- Administration, Utilisateurs, `hotline` : renseignez l'adresse e-mail de la hotline.
- Administration, Paramètres, onglet Régional : vérifiez langue « Français » et fuseau
  « Europe/Paris ».

### 6e. Contrôle « aucune trace »

```bash
/opt/affichage-kit/06-identite/verifier-aucune-trace.sh
```

À me transmettre : les blocs `PALIER 6a`, `6b` et `6c` sans identifiants, une capture de
la page de connexion, et « e-mail de test reçu ».

## Étape 7 — Sauvegarde externe et test de restauration (30 min)

Où : le VPS, en root.

1. Déclarez la destination créée à l'étape 0b, en suivant la section 3 de
   `07-sauvegarde/object-storage-ovh.md` :

   ```bash
   rclone config
   ```

2. Installez et exécutez :

   ```bash
   /opt/affichage-kit/07-sauvegarde/installer-sauvegarde.sh --remote proxyphar-backup:proxyphar-affichage-sauvegardes/intranet --executer
   ```

   Le script installe la minuterie de 03 h 15, réalise une première sauvegarde vers
   l'Object Storage, puis restaure cette sauvegarde sur une copie et compare les
   compteurs. Il doit afficher `RESTAURATION VALIDÉE`. Ensuite :

   ```bash
   /opt/affichage/bin/affichage-restore.sh --nettoyer
   ```

3. Manager OVHcloud, VPS `vps-322ffb27`, onglet **Sauvegarde automatisée** : vérifiez
   l'état « Activé » et faites une capture.

À me transmettre : le bloc `PALIER 7`, la ligne `RESTAURATION VALIDÉE`, la capture du
manager.

## Étape 8 — Recette (1 h, dont player)

Où : le VPS, le navigateur, un player de test.

1. Contrôles automatiques :

   ```bash
   /opt/affichage-kit/08-recette/recette.sh
   ```

2. Dans le navigateur, avec le compte `hotline` : changez le mot de passe demandé,
   ajoutez un média dans la bibliothèque, créez une mise en page « Recette PROXYPHAR »
   avec ce média, publiez-la. Vérifiez que les menus Administration ne sont pas visibles.

3. Player de test : sur un PC Windows du réseau PROXYPHAR, installez le player Windows
   de l'éditeur en version 4.x, puis suivez `/opt/affichage/DOCS/02-enrolement-player.md`
   avec l'adresse `https://intranet.proxyphar.fr` et la clé CMS du coffre. Autorisez
   l'écran dans le CMS, planifiez la mise en page « Recette PROXYPHAR », vérifiez
   l'affichage, puis testez « Collecter maintenant » depuis la page Écrans.

4. Redémarrage complet :

   ```bash
   reboot
   ```

   Après deux minutes, reconnectez-vous et lancez :

   ```bash
   sudo /opt/affichage-kit/08-recette/recette.sh --apres-redemarrage
   ```

5. Renseignez `08-recette/checklist-recette.md`, point par point.

À me transmettre : les deux blocs `PALIER 8`, une photo de l'écran du player, une
capture de la page Écrans avec l'état vert, et la checklist remplie.

## Étape 9 — Clôture (10 min)

- La documentation est dans `/opt/affichage/DOCS/` sur le VPS et dans `09-docs/` du
  dépôt. Vérifiez qu'elle s'ouvre : `ls /opt/affichage/DOCS`.
- Le coffre du service doit contenir sept entrées : clé SSH privée et sa phrase de passe,
  mot de passe MySQL, compte `admin_proxyphar`, compte `hotline`, clé CMS, identifiants S3
  Object Storage, mot de passe d'application Google.
- Conservez `/opt/affichage-kit` sur le VPS : il sert aux mises à jour et aux contrôles.
- Supprimez la mise en page et le média de recette si vous ne les gardez pas.

À me transmettre : « clôture faite ». Je produirai alors le compte rendu final de
déploiement, avec les versions figées et l'état de chaque contrôle.

---

## Récapitulatif des transmissions attendues

| Étape | Transmission |
|-------|--------------|
| 0a | « clé générée » |
| 0b | nom du conteneur et endpoint S3 |
| 0c | adresse de la boîte expéditrice |
| 0d | heure de fin de réinstallation, « connexion ubuntu OK » |
| 0e | sortie de `ls /opt/affichage-kit` |
| 1 | bloc PALIER 1 à 0 écart |
| 2 | bloc PALIER 2, « connexion proxyadmin OK, ubuntu verrouillé » |
| 3 | bloc PALIER 3 à 0 écart |
| 4 | bloc PALIER 4 sans identifiants |
| 5 | bloc PALIER 5, capture SSL Labs |
| 6 | blocs PALIER 6a à 6c sans identifiants, capture de la page de connexion, « e-mail de test reçu » |
| 7 | bloc PALIER 7, « RESTAURATION VALIDÉE », capture du manager |
| 8 | blocs PALIER 8, photo du player, capture Écrans, checklist |
| 9 | « clôture faite » |
