# ============================================================
#  term.s — repli en mode terminal (console Windows, UTF-8, couleurs ANSI)
#
#  Utilisé quand la fenêtre graphique est impossible ou trop lente, même en mode Éco :
#  mêmes règles, même bot, mêmes variables de jeu (game.s), interface en texte.
#  Appel : term_main (ne revient jamais). Option de lancement : 421.exe -t
# ============================================================

.section .rdata,"dr"
tc_red:  .asciz "\033[91m"
tc_yel:  .asciz "\033[93m"
tc_cyn:  .asciz "\033[96m"
tc_mag:  .asciz "\033[95m"
tm_nl:   .asciz "\n"
tm_gap:  .asciz "\033[0m "
tm_sp:   .asciz " "
tm_indent: .asciz "  "
tm_up5:  .asciz "\033[5A"
tm_top:  .asciz "┌───────┐"
tm_bot:  .asciz "└───────┘"
tm_vert: .asciz "│"
tm_pip:  .asciz "●"
tm_pipsp:.asciz "● "
tm_slash:.asciz "/"
tm_rst2: .asciz "\033[0m  "

tm_title:
    .ascii "\033[2J\033[H\n\033[1;93m"
    .ascii "  ╔═══════════════════════════════╗\n"
    .ascii "  ║    \033[91m4 2 1\033[93m  ·  jeu du bistro    ║\n"
    .ascii "  ╚═══════════════════════════════╝\033[0m\n\n"
    .ascii "  Mode terminal : la fenêtre graphique n'est pas disponible ou trop lente ici.\n\n"
    .ascii "  Tu joues contre le bot. Le perdant de la manche prend dans le pot les jetons de\n"
    .ascii "  la combinaison gagnante ; pot vide, le gagnant repasse les siens ; le premier\n"
    .ascii "  sans jeton gagne. 3 lancers max, le 2e joueur ne peut pas lancer plus de fois\n"
    .ascii "  que le 1er. On peut garder des dés entre les lancers.\n\n"
    .asciz "  \033[1m421\033[0m (8) > \033[1m111\033[0m (7) > \033[1m11X\033[0m et \033[1mXXX\033[0m (X jetons) > \033[1msuites\033[0m (2) > le reste (1)\n"

tm_s_round1: .asciz "\n\033[1;97m  ══════ Manche "
tm_s_round2: .asciz " ══════\033[0m\n"
tm_l_pot:    .asciz "  \033[93mPot \033[0m "
tm_l_toi:    .asciz "  \033[96mToi \033[0m "
tm_l_bot:    .asciz "  \033[95mBot \033[0m "
tm_s_youstart: .asciz "\n  \033[96mTu commences\033[0m : jusqu'à 3 lancers.\n\n"
tm_s_botstart: .asciz "\n  \033[95mLe bot commence\033[0m : jusqu'à 3 lancers.\n\n"
tm_s_limbot1:  .asciz "\n  Le bot peut lancer "
tm_s_limbot2:  .asciz " fois au maximum.\n\n"
tm_s_limyou1:  .asciz "\n  Le bot s'arrête. Tu peux lancer "
tm_s_press:    .asciz "  \033[96m[Entrée]\033[0m pour lancer les dés (q = quitter) "
tm_s_ask:      .asciz "  Relancer quels dés ? \033[90m(ex : 13 · Entrée = garder · q = quitter)\033[0m > "
tm_s_bthrows:  .asciz "  \033[95mLe bot lance les dés…\033[0m\n"
tm_s_brel1:    .asciz "  \033[95mLe bot relance \033[0m"
tm_s_brel2:    .asciz " dé(s).\n"
tm_s_lancer:   .asciz "\033[97m  Lancer "
tm_s_dash:     .asciz " — \033[1;92m"
tm_s_nlr:      .asciz "\033[0m\n"
tm_s_recap1:   .asciz "\n  \033[96mToi\033[0m : "
tm_s_recap2:   .asciz "      \033[95mBot\033[0m : "
tm_s_winr:     .asciz "  \033[1;92mTu gagnes la manche !\033[0m Le bot encaisse "
tm_s_losr:     .asciz "  \033[1;91mLe bot gagne la manche.\033[0m Tu encaisses "
tm_s_jet:      .asciz " jeton(s).\n"
tm_s_tie:      .asciz "  \033[93mÉgalité !\033[0m On rejoue la manche.\n"
tm_s_victory:  .asciz "\n  \033[1;92m★ VICTOIRE ! Tu as battu le bot. ★\033[0m\n"
tm_s_defeat:   .asciz "\n  \033[1;91m✖ Le bot gagne la partie.\033[0m\n"
tm_s_again:    .asciz "\n  Rejouer ? (o/n) "
tm_s_bye:      .asciz "\033[0m\n  À la prochaine !\n\n"

tn_0: .asciz "421 !!!"
tn_1: .asciz "Trois as (111)"
tn_2: .asciz "Deux as"
tn_3: .asciz "Brelan"
tn_4: .asciz "Suite"
tn_5: .asciz "Nénette (221)"
tn_6: .asciz "Rien"
.balign 8
tnames: .quad tn_0, tn_1, tn_2, tn_3, tn_4, tn_5, tn_6

.data
.balign 8
tm_vt:      .long 1                 # 1 = séquences ANSI utilisables

.bss
.balign 8
tm_hin:     .skip 8
tm_hout:    .skip 8
tm_col:     .skip 8
tm_written: .skip 8
tm_mode:    .skip 4
tm_nb:      .skip 16
tm_inbuf:   .skip 64
tm_obuf:    .skip 8192

.text

# tm_write : rsi = octets, edx = longueur (retire les séquences ESC [ ... lettre si la console ne les gère pas)
tm_write:
    ENTER
    mov r12, rsi
    mov r13d, edx
    cmp dword ptr [rip+tm_vt], 0
    jne .Ltw_raw
    lea rdi, [rip+tm_obuf]
    xor ecx, ecx
    xor r14d, r14d
.Ltw_l:
    cmp ecx, r13d
    jae .Ltw_out
    mov al, byte ptr [r12+rcx]
    inc ecx
    cmp al, 27
    je .Ltw_esc
    mov byte ptr [rdi+r14], al
    inc r14d
    cmp r14d, 8000
    jb .Ltw_l
    jmp .Ltw_out
.Ltw_esc:
    cmp ecx, r13d
    jae .Ltw_out
    mov al, byte ptr [r12+rcx]
    inc ecx
    or al, 0x20
    cmp al, 'a'
    jb .Ltw_esc
    cmp al, 'z'
    ja .Ltw_esc
    jmp .Ltw_l
.Ltw_out:
    lea r12, [rip+tm_obuf]
    mov r13d, r14d
.Ltw_raw:
    test r13d, r13d
    jz .Ltw_end
    mov rcx, qword ptr [rip+tm_hout]
    mov rdx, r12
    mov r8d, r13d
    lea r9, [rip+tm_written]
    mov qword ptr [rsp+32], 0
    call WriteFile
.Ltw_end:
    LEAVE

# tm_puts : rsi = chaîne terminée par 0
tm_puts:
    ENTER
    mov r12, rsi
    call strlen_z
    mov edx, eax
    mov rsi, r12
    call tm_write
    LEAVE

# tm_putnum : eax = nombre 0..999
tm_putnum:
    ENTER
    lea r8, [rip+tm_nb+15]
    mov byte ptr [r8], 0
    mov r9d, 10
1:  xor edx, edx
    div r9d
    add dl, 48
    dec r8
    mov byte ptr [r8], dl
    test eax, eax
    jnz 1b
    mov rsi, r8
    call tm_puts
    LEAVE

# tm_bar : eax = nombre de jetons dessinés (●)
tm_bar:
    ENTER
    mov r12d, eax
    test r12d, r12d
    jz 2f
1:  lea rsi, [rip+tm_pipsp]
    call tm_puts
    dec r12d
    jnz 1b
2:  LEAVE

# tm_readline : eax = octets lus dans tm_inbuf (0 = fin de saisie)
tm_readline:
    ENTER
    mov rcx, qword ptr [rip+tm_hin]
    lea rdx, [rip+tm_inbuf]
    mov r8d, 64
    lea r9, [rip+tm_written]
    mov qword ptr [rsp+32], 0
    call ReadFile
    test eax, eax
    jz 1f
    mov eax, dword ptr [rip+tm_written]
    jmp 2f
1:  xor eax, eax
2:  LEAVE

tm_sleep:                           # ecx = millisecondes
    sub rsp, 40
    call Sleep
    add rsp, 40
    ret

tm_quit:
    lea rsi, [rip+tm_s_bye]
    call tm_puts
    xor ecx, ecx
    call ExitProcess

# tm_rand6 : eax = 1..6
tm_rand6:
    sub rsp, 40
    call rng_next
    mov ecx, 6
    mul ecx
    lea eax, [rdx+1]
    add rsp, 40
    ret

# tm_dice : ecx = indice du premier dé (0 = toi, 3 = bot), tm_col = couleur du cadre. Dessine 5 lignes.
tm_dice:
    ENTER
    imul eax, ecx, DSTRIDE
    lea r13, [rip+g_dice]
    add r13, rax
    xor r14d, r14d
.Ltd_row:
    lea rsi, [rip+tm_indent]
    call tm_puts
    xor r15d, r15d
.Ltd_die:
    mov rsi, qword ptr [rip+tm_col]
    call tm_puts
    test r14d, r14d
    jnz 1f
    lea rsi, [rip+tm_top]
    call tm_puts
    jmp .Ltd_next
1:  cmp r14d, 4
    jne 2f
    lea rsi, [rip+tm_bot]
    call tm_puts
    jmp .Ltd_next
2:  lea rsi, [rip+tm_vert]
    call tm_puts
    imul eax, r15d, DSTRIDE
    mov ebx, dword ptr [r13+rax+D_VAL]
    lea rdx, [rip+k_pipmask]
    movzx r12d, word ptr [rdx+rbx*2-2]
    lea ecx, [r14-1]
    lea ecx, [rcx+rcx*2]
    shr r12d, cl
    xor edi, edi
3:  lea rsi, [rip+tm_sp]
    call tm_puts
    bt r12d, edi
    jnc 4f
    lea rsi, [rip+tc_yel]
    cmp ebx, 1
    jne 5f
    lea rsi, [rip+tc_red]
5:  call tm_puts
    lea rsi, [rip+tm_pip]
    call tm_puts
    mov rsi, qword ptr [rip+tm_col]
    call tm_puts
    jmp 6f
4:  lea rsi, [rip+tm_sp]
    call tm_puts
6:  inc edi
    cmp edi, 3
    jb 3b
    lea rsi, [rip+tm_sp]
    call tm_puts
    lea rsi, [rip+tm_vert]
    call tm_puts
.Ltd_next:
    lea rsi, [rip+tm_gap]
    call tm_puts
    inc r15d
    cmp r15d, 3
    jb .Ltd_die
    lea rsi, [rip+tm_nl]
    call tm_puts
    inc r14d
    cmp r14d, 5
    jb .Ltd_row
    LEAVE

# tm_roll_anim : ecx = premier dé, edx = masque des dés à lancer (bits 0-2). Anime puis laisse le résultat.
tm_roll_anim:
    ENTER
    mov r12d, ecx
    mov r13d, edx
    mov r14d, 9
    cmp dword ptr [rip+tm_vt], 0
    jne .Lra_f
    mov r14d, 1                     # pas de déplacement du curseur : une seule image
.Lra_f:
    xor r15d, r15d
.Lra_d:
    bt r13d, r15d
    jnc 1f
    call tm_rand6
    lea ecx, [r12+r15]
    imul ecx, ecx, DSTRIDE
    lea rdx, [rip+g_dice]
    mov dword ptr [rdx+rcx+D_VAL], eax
1:  inc r15d
    cmp r15d, 3
    jb .Lra_d
    mov ecx, r12d
    call tm_dice
    dec r14d
    jz .Lra_end
    mov ecx, 70
    call tm_sleep
    lea rsi, [rip+tm_up5]
    call tm_puts
    jmp .Lra_f
.Lra_end:
    LEAVE

# tm_info : ecx = premier dé, edx = numéro du lancer. Affiche "Lancer k/n — combinaison" ([g_lim] = n).
tm_info:
    ENTER
    mov r12d, edx
    call score_hand
    mov r13d, ecx
    lea rsi, [rip+tm_s_lancer]
    call tm_puts
    mov eax, r12d
    call tm_putnum
    lea rsi, [rip+tm_slash]
    call tm_puts
    mov eax, dword ptr [rip+g_lim]
    call tm_putnum
    lea rsi, [rip+tm_s_dash]
    call tm_puts
    lea rax, [rip+tnames]
    mov rsi, qword ptr [rax+r13*8]
    call tm_puts
    lea rsi, [rip+tm_s_nlr]
    call tm_puts
    LEAVE

# tm_player_turn : [g_lim] = lancers autorisés ; résultat dans les dés 0-2 et g_pthrows
tm_player_turn:
    ENTER
    lea rax, [rip+tc_cyn]
    mov qword ptr [rip+tm_col], rax
    lea rsi, [rip+tm_s_press]
    call tm_puts
    call tm_readline
    test eax, eax
    jz tm_quit
    cmp byte ptr [rip+tm_inbuf], 113
    je tm_quit
    mov dword ptr [rip+g_pthrows], 0
    mov r12d, 7
.Lpt_roll:
    xor ecx, ecx
    mov edx, r12d
    call tm_roll_anim
    inc dword ptr [rip+g_pthrows]
    xor ecx, ecx
    mov edx, dword ptr [rip+g_pthrows]
    call tm_info
    mov eax, dword ptr [rip+g_pthrows]
    cmp eax, dword ptr [rip+g_lim]
    jae .Lpt_done
    lea rsi, [rip+tm_s_ask]
    call tm_puts
    call tm_readline
    test eax, eax
    jz tm_quit
    cmp byte ptr [rip+tm_inbuf], 113
    je tm_quit
    mov r13d, eax
    xor r12d, r12d
    lea rdi, [rip+tm_inbuf]
1:  movzx eax, byte ptr [rdi]
    inc rdi
    sub eax, 49
    cmp eax, 2
    ja 2f
    bts r12d, eax
2:  dec r13d
    jnz 1b
    test r12d, r12d
    jnz .Lpt_roll
.Lpt_done:
    LEAVE

# tm_bot_turn : [g_lim] = lancers autorisés, [g_target] = rang à battre (0 = il commence)
tm_bot_turn:
    ENTER
    lea rax, [rip+tc_mag]
    mov qword ptr [rip+tm_col], rax
    lea rsi, [rip+tm_s_bthrows]
    call tm_puts
    mov ecx, 600
    call tm_sleep
    mov dword ptr [rip+g_bthrows], 0
    mov r12d, 7
.Lbt_roll:
    mov ecx, 3
    mov edx, r12d
    call tm_roll_anim
    inc dword ptr [rip+g_bthrows]
    mov ecx, 3
    mov edx, dword ptr [rip+g_bthrows]
    call tm_info
    mov eax, dword ptr [rip+g_bthrows]
    cmp eax, dword ptr [rip+g_lim]
    jae .Lbt_done
    mov ecx, 3
    call score_hand
    mov r13d, eax
    cmp r13d, 700
    jae .Lbt_done
    mov edx, dword ptr [rip+g_target]
    test edx, edx
    jz 1f
    cmp r13d, edx
    ja .Lbt_done
1:  xor r12d, r12d                  # il garde les as, un 2 et un 4
    xor r14d, r14d
    xor r15d, r15d
.Lbt_m:
    imul eax, r15d, DSTRIDE
    lea rcx, [rip+g_dice+3*DSTRIDE]
    mov eax, dword ptr [rcx+rax+D_VAL]
    cmp eax, 1
    je .Lbt_keep
    cmp eax, 2
    jne 2f
    bts r14d, 0
    jnc .Lbt_keep
    jmp .Lbt_re
2:  cmp eax, 4
    jne .Lbt_re
    bts r14d, 1
    jnc .Lbt_keep
.Lbt_re:
    bts r12d, r15d
.Lbt_keep:
    inc r15d
    cmp r15d, 3
    jb .Lbt_m
    test r12d, r12d
    jz .Lbt_done
    mov eax, r12d
    xor r13d, r13d
3:  test eax, eax
    jz 4f
    mov edx, eax
    dec edx
    and eax, edx
    inc r13d
    jmp 3b
4:  lea rsi, [rip+tm_s_brel1]
    call tm_puts
    mov eax, r13d
    call tm_putnum
    lea rsi, [rip+tm_s_brel2]
    call tm_puts
    mov ecx, 800
    call tm_sleep
    jmp .Lbt_roll
.Lbt_done:
    mov ecx, 700
    call tm_sleep
    LEAVE

# tm_statline : rsi = étiquette, eax = nombre de jetons
tm_statline:
    ENTER
    mov r13d, eax
    call tm_puts
    mov eax, r13d
    call tm_bar
    lea rsi, [rip+tm_rst2]
    call tm_puts
    mov eax, r13d
    call tm_putnum
    lea rsi, [rip+tm_nl]
    call tm_puts
    LEAVE

tm_status:
    ENTER
    lea rsi, [rip+tm_s_round1]
    call tm_puts
    mov eax, dword ptr [rip+g_round]
    call tm_putnum
    lea rsi, [rip+tm_s_round2]
    call tm_puts
    lea rsi, [rip+tm_l_pot]
    mov eax, dword ptr [rip+g_pot]
    call tm_statline
    lea rsi, [rip+tm_l_toi]
    mov eax, dword ptr [rip+g_ptok]
    call tm_statline
    lea rsi, [rip+tm_l_bot]
    mov eax, dword ptr [rip+g_btok]
    call tm_statline
    LEAVE

# tm_init : poignées d'entrée/sortie (console existante, redirection ou nouvelle console), UTF-8, ANSI
tm_init:
    ENTER
    mov ecx, -11                    # STD_OUTPUT_HANDLE
    call GetStdHandle
    mov r12, rax
    mov ecx, -10                    # STD_INPUT_HANDLE
    call GetStdHandle
    mov r13, rax
    test r12, r12
    jz 1f
    cmp r12, -1
    je 1f
    test r13, r13
    jz 1f
    cmp r13, -1
    jne 2f
1:  call AllocConsole
    mov ecx, -11
    call GetStdHandle
    mov r12, rax
    mov ecx, -10
    call GetStdHandle
    mov r13, rax
2:  mov qword ptr [rip+tm_hout], r12
    mov qword ptr [rip+tm_hin], r13
    mov ecx, 65001
    call SetConsoleOutputCP
    mov ecx, 65001
    call SetConsoleCP
    mov rcx, r12
    lea rdx, [rip+tm_mode]
    call GetConsoleMode
    test eax, eax
    jz 3f                           # sortie redirigée : on laisse les séquences telles quelles
    mov edx, dword ptr [rip+tm_mode]
    or edx, 5                       # ENABLE_PROCESSED_OUTPUT | ENABLE_VIRTUAL_TERMINAL_PROCESSING
    mov rcx, r12
    call SetConsoleMode
    test eax, eax
    jnz 3f
    mov dword ptr [rip+tm_vt], 0    # console sans ANSI : on retire les séquences
3:  LEAVE

# term_main : partie complète en mode terminal. Ne revient jamais.
term_main:
    ENTER
    call tm_init
    lea rsi, [rip+tm_title]
    call tm_puts
.Ltm_new:
    mov dword ptr [rip+g_pot], POT_INIT
    mov dword ptr [rip+g_ptok], 0
    mov dword ptr [rip+g_btok], 0
    mov dword ptr [rip+g_starter], 0
    mov dword ptr [rip+g_round], 0
.Ltm_round:
    inc dword ptr [rip+g_round]
    call tm_status
    cmp dword ptr [rip+g_starter], 0
    jne .Ltm_botfirst
    lea rsi, [rip+tm_s_youstart]
    call tm_puts
    mov dword ptr [rip+g_lim], 3
    call tm_player_turn
    xor ecx, ecx
    call score_hand
    mov dword ptr [rip+g_target], eax
    lea rsi, [rip+tm_s_limbot1]
    call tm_puts
    mov eax, dword ptr [rip+g_pthrows]
    mov dword ptr [rip+g_lim], eax
    call tm_putnum
    lea rsi, [rip+tm_s_limbot2]
    call tm_puts
    call tm_bot_turn
    jmp .Ltm_resolve
.Ltm_botfirst:
    lea rsi, [rip+tm_s_botstart]
    call tm_puts
    mov dword ptr [rip+g_target], 0
    mov dword ptr [rip+g_lim], 3
    call tm_bot_turn
    lea rsi, [rip+tm_s_limyou1]
    call tm_puts
    mov eax, dword ptr [rip+g_bthrows]
    mov dword ptr [rip+g_lim], eax
    call tm_putnum
    lea rsi, [rip+tm_s_limbot2]
    call tm_puts
    call tm_player_turn
.Ltm_resolve:
    xor ecx, ecx
    call score_hand
    mov dword ptr [rip+g_prank], eax
    mov dword ptr [rip+g_ptokw], edx
    mov dword ptr [rip+g_pcat], ecx
    mov ecx, 3
    call score_hand
    mov dword ptr [rip+g_brank], eax
    mov dword ptr [rip+g_btokw], edx
    mov dword ptr [rip+g_bcat], ecx
    lea rsi, [rip+tm_s_recap1]
    call tm_puts
    lea rax, [rip+tnames]
    mov ecx, dword ptr [rip+g_pcat]
    mov rsi, qword ptr [rax+rcx*8]
    call tm_puts
    lea rsi, [rip+tm_s_recap2]
    call tm_puts
    lea rax, [rip+tnames]
    mov ecx, dword ptr [rip+g_bcat]
    mov rsi, qword ptr [rax+rcx*8]
    call tm_puts
    lea rsi, [rip+tm_nl]
    call tm_puts
    mov eax, dword ptr [rip+g_prank]
    cmp eax, dword ptr [rip+g_brank]
    je .Ltm_tie
    ja .Ltm_you
    mov edi, dword ptr [rip+g_btokw]
    lea rsi, [rip+g_btok]
    lea rdx, [rip+g_ptok]
    call transfer
    mov r12d, eax
    mov dword ptr [rip+g_starter], 0
    lea rsi, [rip+tm_s_losr]
    call tm_puts
    jmp .Ltm_jet
.Ltm_you:
    mov edi, dword ptr [rip+g_ptokw]
    lea rsi, [rip+g_ptok]
    lea rdx, [rip+g_btok]
    call transfer
    mov r12d, eax
    mov dword ptr [rip+g_starter], 1
    lea rsi, [rip+tm_s_winr]
    call tm_puts
.Ltm_jet:
    mov eax, r12d
    call tm_putnum
    lea rsi, [rip+tm_s_jet]
    call tm_puts
    cmp dword ptr [rip+g_pot], 0
    jne .Ltm_round
    cmp dword ptr [rip+g_ptok], 0
    je .Ltm_win
    cmp dword ptr [rip+g_btok], 0
    je .Ltm_lose
    jmp .Ltm_round
.Ltm_tie:
    lea rsi, [rip+tm_s_tie]
    call tm_puts
    jmp .Ltm_round
.Ltm_win:
    lea rsi, [rip+tm_s_victory]
    call tm_puts
    jmp .Ltm_ask
.Ltm_lose:
    lea rsi, [rip+tm_s_defeat]
    call tm_puts
.Ltm_ask:
    lea rsi, [rip+tm_s_again]
    call tm_puts
    call tm_readline
    test eax, eax
    jz tm_quit
    movzx eax, byte ptr [rip+tm_inbuf]
    or eax, 0x20
    cmp eax, 111
    jne tm_quit
    jmp .Ltm_new
