# 421 en 3D isométrique (assembleur x86-64, Windows)

Jeu du 421 contre un bot, dans une fenêtre Windows : table ronde verte, jetons, dés et boutons dessinés
en projection isométrique (rotation 3D réelle des dés pendant le lancer). Écrit en assembleur GNU `as`
(syntaxe Intel), sans bibliothèque C : uniquement `user32`, `gdi32` et `kernel32` (GDI+ est chargé à la demande).

## Lancer
Double-clic sur `421.exe`.

## Jouer
- **LANCER** : lance les trois dés (3 lancers maximum ; le 2e joueur ne peut pas lancer plus de fois que le 1er).
- Clique sur les dés à **relancer** (ils se soulèvent, disque doré), puis **RELANCER** ; ou **VALIDER** pour garder ta main telle quelle.
- Le perdant de la manche prend dans le pot les jetons de la combinaison gagnante ; pot vide, le gagnant repasse les siens.
  Le premier sans jeton gagne. Valeurs : 421 (8), 111 (7), 11X et XXX (X), suites (2), le reste (1).
- Raccourcis : Espace = bouton du haut, Entrée = VALIDER, F12 = capture `421_shot.bmp`, Échap = quitter.

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
`Q` = mode suivant, `F` = redessin complet, `D` = valeurs de contrôle dans le titre, `B` = budgets minuscules (test de la bascule).

## Repli en mode terminal
Si même le mode Éco est trop lent (plus de 30 ms par image), si la fenêtre ou ses tampons ne peuvent pas être créés,
ou si le décor met plus de 800 ms à se dessiner, le jeu masque la fenêtre et continue **dans une console** (UTF-8,
couleurs ANSI, mêmes règles et même bot). On peut aussi le demander : touche `5`, ou lancer `421.exe -t`.
Dans la console : Entrée pour lancer, chiffres des dés à relancer (ex. `13`), `q` pour quitter.

## Compiler
`build.bat` (utilise le gcc/as/ld de MSYS2 : `C:\msys64\ucrt64\bin`).

## Fichiers
- `421.s` : fenêtre, moteur 3D iso, dés, table, jetons, animation.
- `render.s` : rendu : décor en cache, zones modifiées, modes de qualité, GDI+ à la demande, rastériseur anticrénelé.
- `game.s` : règles, bot, boutons, interface (inclus par `421.s`).
- `term.s` : repli en mode terminal (console), mêmes règles que `game.s`.
- `shot.py`, `autoplay.py`, `bench.py`, `imgdiff.py`, `termtest.py`, `tools.py` : outils de test (captures, partie
  automatique, mesures par mode, comparaison d'images, partie en mode terminal).
