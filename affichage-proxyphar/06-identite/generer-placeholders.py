#!/usr/bin/env python3
"""Génère des visuels PROVISOIRES pour le thème PROXYPHAR (à remplacer par les fichiers
officiels de la charte : logo.svg, logo-dark.svg, logo-icon.svg, favicon.ico,
192x192.png, 512x512.png). Aucune dépendance hors bibliothèque standard.

Usage : python3 generer-placeholders.py [dossier_de_sortie]
"""
import os
import struct
import sys
import zlib

PRIMAIRE = (0x0B, 0x5D, 0x8A)
ACCENT = (0x2F, 0xB3, 0xA3)
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
    """Carré à coins arrondis couleur primaire, lettre « P » blanche en blocs."""
    r = taille // 6
    u = taille / 32.0
    stem = (8 * u, 7 * u, 12 * u, 25 * u)          # x0, y0, x1, y1
    haut = (8 * u, 7 * u, 22 * u, 11 * u)
    milieu = (8 * u, 15 * u, 22 * u, 19 * u)
    droite = (18 * u, 7 * u, 22 * u, 19 * u)

    def dans(rect, x, y):
        return rect[0] <= x < rect[2] and rect[1] <= y < rect[3]

    def pixel(x, y):
        # coins arrondis
        cx = min(max(x, r), taille - 1 - r)
        cy = min(max(y, r), taille - 1 - r)
        if (x - cx) ** 2 + (y - cy) ** 2 > r * r:
            return BLANC
        if any(dans(z, x, y) for z in (stem, haut, milieu, droite)):
            return BLANC
        return PRIMAIRE

    return png(taille, taille, pixel)


def ico_depuis_png(donnees_png, taille):
    en_tete = struct.pack("<HHH", 0, 1, 1)
    entree = struct.pack("<BBBBHHII", taille if taille < 256 else 0, taille if taille < 256 else 0,
                         0, 0, 1, 32, len(donnees_png), 6 + 16)
    return en_tete + entree + donnees_png


def svg_logo(sombre=False):
    texte = "#FFFFFF" if sombre else "#%02X%02X%02X" % PRIMAIRE
    accent = "#%02X%02X%02X" % ACCENT
    return f"""<svg xmlns="http://www.w3.org/2000/svg" width="420" height="96" viewBox="0 0 420 96">
  <!-- Visuel PROVISOIRE - à remplacer par le logo officiel PROXYPHAR -->
  <rect x="4" y="8" width="80" height="80" rx="14" fill="{accent}"/>
  <path d="M28 24h22c11 0 18 6 18 15s-7 15-18 15H38v18H28z M38 33v12h11c4 0 7-2 7-6s-3-6-7-6z" fill="#FFFFFF"/>
  <text x="100" y="52" font-family="Arial, Helvetica, sans-serif" font-size="34" font-weight="700" fill="{texte}" letter-spacing="2">PROXYPHAR</text>
  <text x="102" y="78" font-family="Arial, Helvetica, sans-serif" font-size="16" fill="{texte}">Affichage dynamique</text>
</svg>
"""


def svg_icone():
    accent = "#%02X%02X%02X" % ACCENT
    return f"""<svg xmlns="http://www.w3.org/2000/svg" width="96" height="96" viewBox="0 0 96 96">
  <!-- Visuel PROVISOIRE - à remplacer par l'icône officielle PROXYPHAR -->
  <rect x="4" y="4" width="88" height="88" rx="16" fill="{accent}"/>
  <path d="M30 22h24c12 0 20 7 20 17s-8 17-20 17H41v20H30z M41 32v14h12c5 0 8-3 8-7s-3-7-8-7z" fill="#FFFFFF"/>
</svg>
"""


os.makedirs(SORTIE, exist_ok=True)
with open(os.path.join(SORTIE, "logo.svg"), "w", encoding="utf-8") as f:
    f.write(svg_logo())
with open(os.path.join(SORTIE, "logo-dark.svg"), "w", encoding="utf-8") as f:
    f.write(svg_logo(sombre=True))
with open(os.path.join(SORTIE, "logo-icon.svg"), "w", encoding="utf-8") as f:
    f.write(svg_icone())
for taille in (192, 512):
    with open(os.path.join(SORTIE, f"{taille}x{taille}.png"), "wb") as f:
        f.write(icone(taille))
with open(os.path.join(SORTIE, "favicon.ico"), "wb") as f:
    f.write(ico_depuis_png(icone(64), 64))
print("Visuels provisoires écrits dans", SORTIE)
