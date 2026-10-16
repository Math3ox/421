# 421 en 3D isométrique (assembleur x86-64, Windows)

Jeu du 421 contre un bot, dans une fenêtre Windows : table ronde verte, jetons, dés et boutons dessinés
en projection isométrique (rotation 3D réelle des dés pendant le lancer). Écrit en assembleur GNU `as`
(syntaxe Intel), sans bibliothèque C : uniquement `user32`, `gdi32` et `kernel32`.

## Lancer
Double-clic sur `421.exe`.

## Jouer
- **LANCER** : lance les trois dés (3 lancers maximum ; le 2e joueur ne peut pas lancer plus de fois que le 1er).
- Clique sur les dés à **garder** (ils se soulèvent, disque doré), puis **RELANCER** les autres ou **VALIDER**.
- Le perdant de la manche prend dans le pot les jetons de la combinaison gagnante ; pot vide, le gagnant repasse les siens.
  Le premier sans jeton gagne. Valeurs : 421 (8), 111 (7), 11X et XXX (X), suites (2), le reste (1).
- Raccourcis : Espace = bouton du haut, Entrée = VALIDER, F12 = capture `421_shot.bmp`, Échap = quitter.

## Compiler
`build.bat` (utilise le gcc/as/ld de MSYS2 : `C:\msys64\ucrt64\bin`).

## Fichiers
- `421.s` : fenêtre, moteur 3D iso, dés, table, jetons, animation.
- `game.s` : règles, bot, boutons, interface (inclus par `421.s`).
- `shot.py`, `autoplay.py`, `tools.py` : outils de test (captures, partie automatique).
