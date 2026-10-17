# 421 en 3D isométrique (assembleur x86-64, Windows)

Jeu du 421 contre un bot (ou à deux sur le même PC), dans une fenêtre Windows : table ronde verte, jetons, dés et
boutons dessinés en projection isométrique (rotation 3D réelle des dés pendant le lancer). Écrit en assembleur GNU `as`
(syntaxe Intel), sans bibliothèque C : uniquement `user32`, `gdi32` et `kernel32` (GDI+ est chargé à la demande).

## Lancer
Double-clic sur `421.exe` (62-72 Ko, aucune installation).

## Jouer
- **LANCER** : lance les trois dés (3 lancers maximum ; le 2e joueur ne peut pas lancer plus de fois que le 1er).
- Clique sur les dés à **relancer** (ils se soulèvent, disque doré), puis **RELANCER** ; ou **VALIDER** pour garder ta main telle quelle.
- Le perdant de la manche prend dans le pot les jetons de la combinaison gagnante ; pot vide, le gagnant repasse les siens.
  Le premier sans jeton gagne. Valeurs : 421 (8), 111 (7), 11X et XXX (X), suites (2), le reste (1).
- Raccourcis : Espace = bouton du haut, Entrée = VALIDER, F12 = capture `421_shot.bmp`, Échap = quitter.

## Taille de la fenêtre
La fenêtre fait 1100x800 si l'écran le permet ; sur un écran plus petit (ou très zoomé, ex. portable à 150 %), elle est
réduite automatiquement pour tenir entièrement dans la zone de travail et centrée. Le jeu s'affiche alors mis à l'échelle
(seule la zone modifiée est recopiée), les clics restent justes.

## Options (rappelées en bas de la fenêtre)
| Touche | Effet |
|---|---|
| `J` | 1 joueur contre le bot ↔ **2 joueurs sur le même PC** (chacun son tour, mêmes boutons ; nouvelle partie) |
| `L` | niveau du bot : facile → normal → difficile |
| `H` | **aide** pendant le choix des dés : probabilité de 421 et de « mieux » pour les dés sélectionnés + conseil optimal |
| `P` | pot de départ 7 / 11 / 15 / 21 jetons (à la prochaine partie) |
| `F11` | **plein écran** : le jeu est agrandi pour remplir l'écran (proportions gardées, bandes noires sur les côtés si besoin). Échap en sort |

Niveaux du bot : *facile* = stratégie normale avec 35 % de décisions au hasard ; *normal* = garde les as, un 2 et un 4 ;
*difficile* = stratégie **optimale** (programmation dynamique sur les 56 mains possibles, utilité en jetons). En simulation :
difficile bat normal dans ~58 % des parties, normal bat facile dans ~63 %.

Les réglages (mode de rendu, pot, niveau, 1/2 joueurs, plein écran, victoires/défaites contre le bot) sont mémorisés dans
`421.cfg` (32 octets) créé à côté de l'exécutable ; supprimer ce fichier remet les valeurs par défaut.

## Multijoueur en ligne (duel à 2, IP directe)
Touche **N** : un joueur choisit **H** (héberger), l'autre **R** (rejoindre) et tape l'IP de l'hôte (port 4210 par défaut,
ou `ip:port`) puis Entrée ; Échap annule, `N` coupe la connexion. L'hôte est le joueur 1, l'invité le joueur 2.
- L'hôte voit ses adresses IP à l'écran. Réseau local : la sienne (192.168.x.x). Par Internet : **VPN type Tailscale / ZeroTier**
  (donner l'IP du VPN) ou **redirection du port TCP 4210** sur la box. Le pare-feu Windows demandera d'autoriser le jeu.
- Principe « lockstep » : les deux PC exécutent la même partie avec le même générateur aléatoire (graine envoyée par l'hôte) ;
  seules les **actions** (lancer, dés cochés, valider, suivant, rejouer) sont échangées, 12 octets chacune. Les deux joueurs
  doivent avoir la même version du jeu. Si la connexion tombe, on revient à la partie locale.
- Winsock n'est chargé qu'à l'ouverture du menu : aucun coût hors ligne. La dernière IP saisie est mémorisée dans `421.cfg`.

## Modes de rendu
Le décor est rendu une fois et mis en cache ; à chaque image seule la zone qui bouge est redessinée.
Quatre modes (affichés dans le titre de la fenêtre) :

| Touche | Mode | Principe |
|---|---|---|
| `1` | Haute | GDI dans un tampon 2x réduit par moyenne 2x2 (SSE) |
| `2` | GDI+ | GDI+ avec anticrénelage, en 1x (DLL chargée à la demande) |
| `3` | Rapide | rastériseur maison en assembleur (couverture exacte), en 1x, ombres translucides |
| `4` | Éco | GDI en 1x sans anticrénelage, 30 images/s |

`0` = qualité automatique (par défaut) : le jeu descend de mode si les images dépassent le budget de 12 ms.
`Q` = mode suivant, `F` = redessin complet, `D` = valeurs de contrôle dans le titre.

## Repli en mode terminal
Si même le mode Éco est trop lent (plus de 30 ms par image), si la fenêtre ou ses tampons ne peuvent pas être créés,
ou si le décor met plus de 800 ms à se dessiner, le jeu masque la fenêtre et continue **dans une console** (UTF-8,
couleurs ANSI, mêmes règles et même bot). On peut aussi le demander : touche `5`, ou lancer `421.exe -t`.
Dans la console : Entrée pour lancer, chiffres des dés à relancer (ex. `13`), `q` pour quitter.

## Compiler
`build.bat` (utilise le gcc/as/ld de MSYS2 : `C:\msys64\ucrt64\bin`). `build_dev.bat` compile un exécutable de **test**
(touches `T` et `B` actives) à ne pas distribuer.

## Fichiers
- `421.s` : fenêtre, moteur 3D iso, dés, table, jetons, animation, plein écran.
- `render.s` : rendu : décor en cache, zones modifiées, modes de qualité, GDI+ à la demande, rastériseur anticrénelé.
- `game.s` : règles, déroulement (1 ou 2 joueurs), boutons, interface (inclus par `421.s`).
- `ai.s` + `aitab.s` : niveaux du bot, calcul de probabilités, aide, réglages mémorisés. `aitab.s` est **généré** par
  `gen_tables.py` (stratégie optimale).
- `net.s` : duel en ligne (Winsock à la demande, protocole 12 octets, file d'actions, saisie de l'IP).
- `term.s` : repli en mode terminal (console), mêmes règles que `game.s`.
- Outils de test : `shot.py` (captures), `autoplay.py` (partie automatique), `bench.py` (mesures par mode),
  `imgdiff.py`, `termtest.py` (partie en terminal), `bottest.py` (décisions du bot asm = stratégie Python),
  `screencap.py` (capture de l'écran, plein écran), `nettest.py` (deux instances jouent en ligne et on vérifie qu'elles
  restent identiques), `netshot.py` (captures des écrans multijoueur), `fstest.py` (plein écran mis à l'échelle + clics), `tools.py`.
