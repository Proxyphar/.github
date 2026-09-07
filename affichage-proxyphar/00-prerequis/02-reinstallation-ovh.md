# Étape 0b — Réinstallation du VPS depuis le manager OVH

> **Action irréversible.** Elle efface l'intégralité du disque du VPS, donc l'instance
> Xibo 3.3.2 « bubu.re » et toutes ses données. Elle n'est lancée qu'après validation
> explicite d'Alexandre.

## Avant de lancer

- [ ] La clé publique `proxyphar-affichage-admin` est générée et prête à être collée (étape 0a).
- [ ] Il est acté qu'aucune donnée de l'instance actuelle ne doit être conservée.
- [ ] Le service concerné est bien `vps-322ffb27.vps.ovh.net` (51.75.251.209).

## Procédure (manager OVHcloud)

1. **Bare Metal Cloud** > **Serveurs privés virtuels** > `vps-322ffb27.vps.ovh.net`.
2. Onglet **Accueil**, bloc **OS / Distribution**, bouton `...` > **Réinstaller mon VPS**.
3. Système : **Ubuntu 24.04**. Ne pas choisir d'image applicative.
4. Clé SSH : coller la clé publique dans **Votre clé SSH Publique**, ou la choisir dans
   **Clé SSH à pré-installer** si elle a été stockée dans l'espace client.
5. Cocher **Je ne souhaite pas recevoir par e-mail les codes d'authentification de mon VPS**.
6. Confirmer. La réinstallation dure en général de 5 à 15 minutes ; un e-mail de fin
   précise l'utilisateur de connexion (`ubuntu` sur les images Ubuntu ; root est désactivé).

## Première connexion

```bash
ssh -i ~/.ssh/proxyphar-affichage ubuntu@51.75.251.209
```

À la première connexion, SSH demande de confirmer l'empreinte du serveur : c'est
normal, le serveur est neuf. Répondez `yes`.

Si la connexion est refusée avec un message d'empreinte différente (`REMOTE HOST
IDENTIFICATION HAS CHANGED`), c'est l'ancienne empreinte mémorisée sur le poste ;
supprimez-la puis reconnectez-vous :

```bash
ssh-keygen -R 51.75.251.209
ssh-keygen -R vps-322ffb27.vps.ovh.net
```

Puis passez à l'étape 1 (`01-post-install/verifier-systeme.sh`).

## Points de vigilance

- Les **sauvegardes automatisées OVH** antérieures à la réinstallation contiennent
  encore l'ancienne instance jusqu'à leur expiration par rotation. Si une purge
  immédiate est exigée, la demander au support OVHcloud : le manager ne permet pas de
  supprimer un point de restauration automatisé à la main.
- L'IPv6 du VPS (`2001:41d0:305:2100::a4c4`) n'est pas toujours configurée
  automatiquement par l'image. L'étape 3 (DNS) vérifie la connectivité IPv6 avant de
  créer l'enregistrement AAAA.
- Le mot de passe root « perdu » n'a plus d'objet : après réinstallation, root n'a pas de
  mot de passe et l'accès se fait par clé.
