#!/usr/bin/env python3
"""Génère les visuels bitmap du thème PROXYPHAR (favicon.ico, 192x192.png, 512x512.png)
aux couleurs du logo : monogramme simplifié violet et rose. À remplacer par les fichiers
officiels s'ils existent. Aucune dépendance hors bibliothèque standard.

Usage : python3 generer-placeholders.py [dossier_de_sortie]
"""
import os
import struct
import sys
import zlib

PRIMAIRE = (0x6B, 0x2D, 0x90)
ACCENT = (0xE6, 0x00, 0x7E)
BLANC = (0xFF, 0xFF, 0xFF)
SORTIE = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), "brand")


def png(largeur, hauteur, pixel):
    """Écrit un PNG RGB à partir d'une fonction pixel(x, y) -> (r, g, b)."""
    lignes = bytearray()
    for y in range(hauteur):
        lignes.append(0)
        for x in range(largeur):
            lignes.extend(pixel(x, y))

    def bloc(tag, data):
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    return (b"\x89PNG\r\n\x1a\n"
            + bloc(b"IHDR", struct.pack(">IIBBBBB", largeur, hauteur, 8, 2, 0, 0, 0))
            + bloc(b"IDAT", zlib.compress(bytes(lignes), 9))
            + bloc(b"IEND", b""))


def icone(taille):
    """Carré blanc à coins arrondis, « P » violet et jambage rose, d'après le monogramme."""
    r = taille // 6
    u = taille / 32.0
    stem = (7 * u, 6 * u, 11 * u, 26 * u)           # jambage violet (x0, y0, x1, y1)
    haut = (7 * u, 6 * u, 21 * u, 10 * u)
    milieu = (7 * u, 15 * u, 21 * u, 19 * u)
    droite = (17 * u, 6 * u, 21 * u, 19 * u)
    rose = (21 * u, 10 * u, 25 * u, 26 * u)          # jambage rose du « q »

    def dans(rect, x, y):
        return rect[0] <= x < rect[2] and rect[1] <= y < rect[3]

    def pixel(x, y):
        cx = min(max(x, r), taille - 1 - r)
        cy = min(max(y, r), taille - 1 - r)
        if (x - cx) ** 2 + (y - cy) ** 2 > r * r:
            return BLANC
        if dans(rose, x, y):
            return ACCENT
        if any(dans(z, x, y) for z in (stem, haut, milieu, droite)):
            return PRIMAIRE
        return BLANC

    return png(taille, taille, pixel)


def ico_depuis_png(donnees_png, taille):
    en_tete = struct.pack("<HHH", 0, 1, 1)
    entree = struct.pack("<BBBBHHII", taille if taille < 256 else 0, taille if taille < 256 else 0,
                         0, 0, 1, 32, len(donnees_png), 6 + 16)
    return en_tete + entree + donnees_png


os.makedirs(SORTIE, exist_ok=True)
for taille in (192, 512):
    with open(os.path.join(SORTIE, f"{taille}x{taille}.png"), "wb") as f:
        f.write(icone(taille))
with open(os.path.join(SORTIE, "favicon.ico"), "wb") as f:
    f.write(ico_depuis_png(icone(64), 64))
print("Visuels bitmap écrits dans", SORTIE)
