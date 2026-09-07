<?php
/*
 * /opt/affichage/shared/cms/custom/settings-custom.php — PROXYPHAR
 * Inclus par le settings.php du conteneur cms-web (Xibo 4.5.2).
 *
 * $trustedProxyIps : adresses depuis lesquelles les en-têtes X-Forwarded-* sont
 *   dignes de confiance. Nginx (hôte) joint cms-web via le port publié 127.0.0.1:8080 ;
 *   le conteneur voit la passerelle du réseau Docker « affichage_default » (172.28.0.1).
 *   Sans cette liste, le CMS appliquerait sa limite de tentatives de connexion
 *   (5 échecs / 15 min) à l'adresse du proxy, donc à tous les utilisateurs à la fois.
 *
 * $whitelistHosts : nom d'hôte canonique du CMS ; toute autre valeur de l'en-tête Host
 *   est remplacée par celui-ci dans les URL générées.
 */
$trustedProxyIps = '172.28.0.0/24,127.0.0.1';
$whitelistHosts = 'intranet.proxyphar.fr';
