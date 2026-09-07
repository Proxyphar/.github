# Étape 8 — Checklist de recette

À remplir point par point. Les contrôles marqués « script » sont exécutés par
`08-recette/recette.sh` ; les autres demandent une action humaine. La recette n'est
acquise que si **toutes** les lignes sont cochées avec la preuve indiquée.

| # | Contrôle | Comment | Preuve à joindre | État |
|---|----------|---------|------------------|------|
| 1 | Accès HTTPS au CMS, certificat valide | script (`verifier-tls.sh`) | sortie du script | ☐ |
| 2 | Note SSL Labs A ou mieux | https://www.ssllabs.com/ssltest/analyze.html?d=intranet.proxyphar.fr | capture de la note | ☐ |
| 3 | Accès par IP nue / nom OVH refusé | script | sortie du script | ☐ |
| 4 | Connexion administrateur (`admin_proxyphar`) | navigateur | capture du tableau de bord | ☐ |
| 5 | Connexion hotline (`hotline`), changement de mot de passe forcé, menus d'administration absents | navigateur | capture du menu latéral | ☐ |
| 6 | Interface en français, heure Europe/Paris, nom « PROXYPHAR Affichage », logo, favicon | navigateur | capture de la page de connexion | ☐ |
| 7 | Aucune trace « bubu » | script (`verifier-aucune-trace.sh`) | sortie du script | ☐ |
| 8 | Envoi d'un média (image ou vidéo) | navigateur : Bibliothèque > Ajouter | capture de la bibliothèque | ☐ |
| 9 | Création d'une mise en page de test « Recette PROXYPHAR » et publication | navigateur : Mises en page | capture | ☐ |
| 10 | Enrôlement d'un player de test (clé CMS), autorisation, diffusion effective de la mise en page | player + navigateur : Écrans | photo de l'écran + capture « Écrans » (état vert) | ☐ |
| 11 | XMR fonctionnel : « Collecter maintenant » depuis le CMS provoque une remontée immédiate | navigateur : Écrans > menu ligne | capture de la date de dernier accès | ☐ |
| 12 | Redémarrage complet du VPS : Nginx, Docker et les 5 conteneurs remontent seuls | `sudo reboot` puis script | sortie de `recette.sh --apres-redemarrage` | ☐ |
| 13 | Sauvegarde exécutée (état `OK`), présente sur la destination externe | script | sortie du script + `rclone lsf` | ☐ |
| 14 | Restauration validée sur copie (`RESTAURATION VALIDÉE`) | `affichage-restore.sh` | journal du script | ☐ |
| 15 | Backup automatisé OVH « Activé » sur le VPS | manager OVH > VPS > Sauvegarde automatisée | capture | ☐ |
| 16 | Pare-feu : seuls 22, 80, 443 ouverts ; fail2ban et unattended-upgrades actifs | script | sortie du script | ☐ |
| 17 | Mots de passe transmis une seule fois et stockés dans le coffre du service | Alexandre | — | ☐ |
| 18 | Documentation présente dans `/opt/affichage/DOCS/` | script | sortie du script | ☐ |

## Déroulé conseillé

1. `sudo /opt/affichage-kit/08-recette/recette.sh` (contrôles 1, 3, 7, 13, 16, 18).
2. Contrôles navigateur 4 à 9 et 11.
3. Player de test (contrôle 10) : procédure `/opt/affichage/DOCS/02-enrolement-player.md`.
   Pour la recette, un player Windows ou Android sur le réseau PROXYPHAR suffit.
4. `sudo reboot`, attendre 2 minutes, `sudo /opt/affichage-kit/08-recette/recette.sh --apres-redemarrage` (contrôle 12).
5. Test de restauration (contrôle 14) : `07-sauvegarde/test-restauration.md`.
6. SSL Labs (contrôle 2) et manager OVH (contrôle 15) depuis un poste.

## Nettoyage après recette

- Supprimer la mise en page et le média de test, ou les conserver comme modèle.
- Supprimer la copie de restauration : `sudo /opt/affichage/bin/affichage-restore.sh --nettoyer`.
- Retirer le player de test des écrans s'il ne sert plus.
