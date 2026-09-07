# Étape 7 — Test de restauration sur copie

Une sauvegarde jamais restaurée n'est pas une sauvegarde. Le déploiement n'est déclaré
terminé qu'après ce test, réalisé **sur une copie** (la production n'est pas touchée).

## Principe

`affichage-restore.sh` récupère une sauvegarde (export SQL + archive `shared/`) depuis la
destination externe, la déploie dans `/opt/affichage-restore-test` sur une pile Docker
distincte (`affichage-test`, port local 8081, sous-réseau distinct), laisse l'entrypoint Xibo
importer la base (`shared/backup/import.sql`), puis compare les compteurs (médias, mises
en page, écrans, utilisateurs) au manifeste écrit au moment de la sauvegarde.

## Déroulé

```bash
sudo /opt/affichage/bin/affichage-backup.sh                       # sauvegarde du jour
sudo /opt/affichage/bin/affichage-restore.sh --sauvegarde derniere # restauration de test
```

Contrôle visuel (facultatif) depuis le poste d'administration :

```bash
ssh -L 8081:127.0.0.1:8081 affichage-proxyphar
```

puis ouvrir `http://localhost:8081/login` dans le navigateur, se connecter avec le
compte administrateur, vérifier la bibliothèque et une mise en page.

Nettoyage obligatoire ensuite (libère la mémoire et le disque) :

```bash
sudo /opt/affichage/bin/affichage-restore.sh --nettoyer
```

## Critères de validation

- le script termine par `RESTAURATION VALIDÉE` ;
- les quatre compteurs sont « conformes » ;
- la connexion administrateur fonctionne sur la copie ;
- la clé CMS et le dossier `library/certs/` sont présents (sans eux, les players
  existants devraient être ré-enrôlés).

## Restauration réelle (sinistre)

Après réinstallation du VPS et exécution des étapes 1 à 5 du kit :

```bash
rclone config                                            # recréer le remote
sudo /opt/affichage/bin/affichage-restore.sh --sauvegarde derniere --production
```

Le dossier `shared` précédent est conservé sous `shared.avant-restauration.<date>` jusqu'à
validation. Procédure détaillée : `/opt/affichage/DOCS/03-sauvegarde-restauration.md`.
