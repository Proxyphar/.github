# Enrôler un nouveau player en officine

Procédure à l'usage de la hotline PROXYPHAR. Durée : 10 minutes sur site, hors
installation physique de l'écran.

## Informations à préparer

| Donnée | Valeur |
|--------|--------|
| Adresse du CMS | `https://intranet.proxyphar.fr` |
| Clé CMS | dans `/opt/affichage/config.env` (ligne `# AFFICHAGE_CMS_KEY=`) ou Administration > Paramètres > Clé CMS |
| Nom de l'écran | `PHARMACIE-<ville>-<usage>` (ex. `PHARMACIE-LILLE-VITRINE`) |
| Compte CMS | `hotline` (ou administrateur) |

Le player doit pouvoir joindre `intranet.proxyphar.fr` en HTTPS (port 443 sortant) depuis
le réseau de l'officine. Aucun autre port n'est nécessaire : les messages instantanés
(XMR) passent par le WebSocket `wss://intranet.proxyphar.fr/xmr`, sur le même port 443.

## Choisir le player

| Support | Player | Remarque |
|---------|--------|----------|
| Boîtier Android ou écran Android professionnel | Xibo for Android (version 4.x) | licence Xibo par player (achat auprès de Xibo Signage) |
| PC Windows derrière l'écran | Xibo for Windows (version 4.x) | gratuit |
| Écran LG webOS / Samsung Tizen | player Xibo dédié | licence Xibo |
| Mini-PC Linux | Xibo for Linux (snap) | connexion par clé CMS uniquement (pas de code) |

Utiliser des players de version **4.x**, cohérents avec le CMS 4.5. Les players 3.x ne
reçoivent pas les messages XMR (port 9505 fermé) et ne sont pas pris en charge.

## Connecter le player au CMS

1. Installer le player, l'ouvrir, aller dans ses **réglages** (Windows : lancer
   « Xibo Player Options » ; Android : bouton de configuration au premier démarrage).
2. **Adresse du CMS** : `https://intranet.proxyphar.fr`.
3. **Clé** : la clé CMS. Alternative : « Connexion par code » (le player affiche un code à
   saisir dans le CMS, Écrans > Ajouter par code). Le player Linux n'a pas cette option.
4. **Nom de l'écran** : nom convenu (voir ci-dessus).
5. Enregistrer. Le player affiche « En attente d'autorisation » ou un écran par défaut.

## Autoriser l'écran dans le CMS

1. Se connecter sur `https://intranet.proxyphar.fr` avec le compte `hotline`.
2. Menu **Écrans** : l'écran apparaît, badge « Non autorisé ».
3. Menu de ligne > **Autoriser**. Ne jamais activer l'autorisation automatique dans les
   paramètres : elle accepterait tout appareil connaissant la clé.
4. Menu de ligne > **Modifier** : dossier, profil de paramètres, fuseau, groupe d'écrans
   de l'officine.
5. Planifier une mise en page (**Planification** > **Ajouter un événement**) ou la
   mise en page par défaut de l'écran.
6. Vérifier : l'écran passe au vert dans **Écrans** (dernier accès à l'instant) et le
   contenu s'affiche. **Collecter maintenant** force une synchronisation immédiate via XMR.

## Vérifications en cas de problème

| Symptôme | Vérification |
|----------|--------------|
| Le player ne s'enregistre pas | depuis le réseau de l'officine, ouvrir `https://intranet.proxyphar.fr` dans un navigateur ; vérifier la clé (sensible à la casse) ; l'heure du player doit être juste (TLS) |
| Écran « Non autorisé » qui reste | l'autorisation n'a pas été faite dans le CMS ; ou le player a changé de clé matérielle après réinstallation : ré-autoriser |
| Contenu qui ne se met pas à jour | intervalle de collecte dans le profil de paramètres ; « Collecter maintenant » ; état XMR dans Écrans > Modifier > onglet Avancé |
| Vidéo qui ne se lit pas | format H.264/AAC en .mp4, résolution ≤ 1080p pour les boîtiers Android d'entrée de gamme |

## Fin d'intervention

Consigner dans la fiche client : nom de l'écran dans le CMS, modèle du player, version,
date d'autorisation, contenu planifié. Retirer la clé CMS de tout support laissé à
l'officine.
