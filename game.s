# ============================================================
#  game.s — règles du 421, bot, boutons 3D, interface (inclus par 421.s)
# ============================================================

.equ PH_PREROLL, 0              # à toi de lancer
.equ PH_ROLLING, 1              # les dés roulent (toi)
.equ PH_CHOOSE,  2              # tu choisis les dés à garder
.equ PH_BOT,     3              # le bot joue
.equ PH_RESULT,  4              # résultat de la manche affiché
.equ PH_OVER,    5              # fin de partie

.equ ACT_BOT_ROLL, 1
.equ ACT_BOT_DONE, 2
.equ ACT_RESOLVE,  3

.equ POT_INIT, 11               # jetons dans le pot au départ

RGB C_BTNG,   255, 196, 64
RGB C_BTNGS,  176, 118, 20
RGB C_BTNB,   96, 200, 255
RGB C_BTNBS,  30, 104, 160
RGB C_BTNX,   92, 106, 100
RGB C_BTNXS,  58, 68, 64
RGB C_BTNTXT, 28, 24, 16
RGB C_BTNTXTX,150, 162, 156

.section .rdata,"dr"
.balign 8
k_btna:     .double 4.9
k_btnbm:    .double -1.0
k_btnbp:    .double 1.0
k_btnr:     .double 1.0
k_btnh:     .double 0.30
k_btntz:    .double 0.41
k_btnoff:   .double 0.18
k_botz:     .double -4.3
k_plz:      .double 4.8
k_pota:     .double -4.6
k_potlz:    .double 0.95
k_toilz:    .double 5.4
k_botlz:    .double -6.0
k_ringr:    .double 1.0, 1.07, 1.14

n_421:  .asciz "421 !!!"
n_111:  .asciz "Trois as (111)"
n_11x:  .asciz "Deux as"
n_xxx:  .asciz "Brelan"
n_sui:  .asciz "Suite"
n_nen:  .asciz "N\351nette (221)"
n_rien: .asciz "Rien"
.balign 8
names:  .quad n_421, n_111, n_11x, n_xxx, n_sui, n_nen, n_rien

l_pot:       .asciz "POT "
l_toi:       .asciz "TOI "
l_bot:       .asciz "BOT "
t_manche:    .asciz "Manche "
t_you_first: .asciz "Tu commences ! Lance les d\351s (3 lancers max)."
t_bot_first: .asciz "Le bot commence..."
t_rolling:   .asciz "Les d\351s roulent..."
t_ch1:       .asciz "Lancer "
t_slash:     .asciz "/"
t_ch2:       .asciz " : clique sur les d\351s \340 garder, puis RELANCER ou VALIDER."
t_toi:       .asciz "Toi : "
t_bot:       .asciz "Bot : "
t_gap:       .asciz "        "
t_bp1:       .asciz "Le bot joue ("
t_bp2:       .asciz " lancer(s) max)..."
t_bthrow:    .asciz "Le bot lance les d\351s..."
t_brel1:     .asciz "Le bot relance "
t_brel2:     .asciz " d\351(s)..."
t_bst1:      .asciz "Le bot s'arr\352te apr\350s "
t_bst2:      .asciz " lancer(s). \300 toi, "
t_bst3:      .asciz " lancer(s) max !"
t_winr:      .asciz "Tu gagnes la manche ! Le bot encaisse "
t_losr:      .asciz "Le bot gagne la manche. Tu encaisses "
t_jet:       .asciz " jeton(s)."
t_tie:       .asciz "\311galit\351 ! On rejoue la manche."
t_victory:   .asciz "VICTOIRE ! Tu as battu le bot."
t_defeat:    .asciz "Le bot gagne la partie."
t_empty:     .asciz ""
b_lancer:    .asciz "LANCER"
b_relancer:  .asciz "RELANCER"
b_valider:   .asciz "VALIDER"
b_suivant:   .asciz "SUIVANT"
b_rejouer:   .asciz "REJOUER"
b_dots:      .asciz "..."

.bss
.balign 8
g_phase:    .skip 4
g_starter:  .skip 4
g_round:    .skip 4
g_pthrows:  .skip 4
g_bthrows:  .skip 4
g_lim:      .skip 4
g_target:   .skip 4
g_who:      .skip 4
g_botmask:  .skip 4
g_wake:     .skip 4
g_wakeact:  .skip 4
g_prank:    .skip 4
g_brank:    .skip 4
g_ptokw:    .skip 4
g_btokw:    .skip 4
g_pcat:     .skip 4
g_bcat:     .skip 4
g_pt1:      .skip 8
.balign 8
g_wp:       .skip 8
g_line1:    .skip 192
g_line2:    .skip 192
g_lbl:      .skip 64
g_numbuf:   .skip 16
hb_px:      .skip 8
hb_py:      .skip 8
bt_a:       .skip 8
bt_b:       .skip 8

.text

# ---------- construction de messages ----------
msg_start:                          # rdi = tampon
    mov qword ptr [rip+g_wp], rdi
    mov byte ptr [rdi], 0
    ret

msg_str:                            # rsi = chaîne
    mov rdi, qword ptr [rip+g_wp]
1:  mov al, byte ptr [rsi]
    mov byte ptr [rdi], al
    test al, al
    jz 2f
    inc rsi
    inc rdi
    jmp 1b
2:  mov qword ptr [rip+g_wp], rdi
    ret

msg_num:                            # eax = nombre (0..999)
    mov rdi, qword ptr [rip+g_wp]
    lea r8, [rip+g_numbuf+15]
    mov byte ptr [r8], 0
    mov r9d, 10
1:  xor edx, edx
    div r9d
    add dl, 48
    dec r8
    mov byte ptr [r8], dl
    test eax, eax
    jnz 1b
2:  mov al, byte ptr [r8]
    mov byte ptr [rdi], al
    test al, al
    jz 3f
    inc r8
    inc rdi
    jmp 2b
3:  mov qword ptr [rip+g_wp], rdi
    ret

msg_name:                           # ecx = catégorie -> ajoute le nom
    lea rdx, [rip+names]
    mov rsi, qword ptr [rdx+rcx*8]
    jmp msg_str

# ---------- règles ----------

# rank3 : r8d, r9d, r10d = les 3 dés.
#   Sortie : eax = rang, edx = jetons, ecx = catégorie (index de names)
rank3:
    cmp r8d, r9d
    jge 1f
    xchg r8d, r9d
1:  cmp r9d, r10d
    jge 2f
    xchg r9d, r10d
2:  cmp r8d, r9d
    jge 3f
    xchg r8d, r9d
3:  cmp r8d, 4                  # 421
    jne 4f
    cmp r9d, 2
    jne 4f
    cmp r10d, 1
    jne 4f
    mov eax, 1000
    mov edx, 8
    xor ecx, ecx
    ret
4:  cmp r8d, 1                  # 111
    jne 5f
    mov eax, 900
    mov edx, 7
    mov ecx, 1
    ret
5:  cmp r8d, r10d               # brelan
    jne 6f
    lea eax, [r8*2+800]
    mov edx, r8d
    mov ecx, 3
    ret
6:  cmp r10d, 1                 # 11X
    jne 7f
    cmp r9d, 1
    jne 7f
    lea eax, [r8*2+801]
    mov edx, r8d
    mov ecx, 2
    ret
7:  lea eax, [r9+1]             # suite
    cmp r8d, eax
    jne 8f
    lea eax, [r10+1]
    cmp r9d, eax
    jne 8f
    lea eax, [r8+700]
    mov edx, 2
    mov ecx, 4
    ret
8:  cmp r8d, 2                  # nénette
    jne 9f
    cmp r9d, 2
    jne 9f
    cmp r10d, 1
    jne 9f
    mov eax, 1
    mov edx, 1
    mov ecx, 5
    ret
9:  imul eax, r8d, 100
    imul ecx, r9d, 10
    add eax, ecx
    add eax, r10d
    mov edx, 1
    mov ecx, 6
    ret

# score_hand : ecx = premier dé de la main (0 = toi, 3 = bot) -> eax, edx, ecx comme rank3
score_hand:
    lea r11, [rip+g_dice]
    imul eax, ecx, DSTRIDE
    add r11, rax
    mov r8d, dword ptr [r11+D_VAL]
    mov r9d, dword ptr [r11+DSTRIDE+D_VAL]
    mov r10d, dword ptr [r11+2*DSTRIDE+D_VAL]
    jmp rank3

# transfer : edi = valeur de la combinaison, rsi = &jetons du gagnant, rdx = &jetons du perdant
#            -> eax = jetons déplacés (pot non vide : pris dans le pot ; sinon donnés par le gagnant)
transfer:
    mov eax, edi
    mov ecx, dword ptr [rip+g_pot]
    test ecx, ecx
    jz 1f
    cmp eax, ecx
    jbe 2f
    mov eax, ecx
2:  sub dword ptr [rip+g_pot], eax
    add dword ptr [rdx], eax
    ret
1:  mov ecx, dword ptr [rsi]
    cmp eax, ecx
    jbe 3f
    mov eax, ecx
3:  sub dword ptr [rsi], eax
    add dword ptr [rdx], eax
    ret

# set_wake : ecx = délai (ms), edx = action à exécuter ensuite
set_wake:
    sub rsp, 40
    mov dword ptr [rip+g_wakeact], edx
    mov r8d, ecx
    call GetTickCount
    add eax, r8d
    or eax, 1
    mov dword ptr [rip+g_wake], eax
    add rsp, 40
    ret

clear_held:
    xor ecx, ecx
1:  imul eax, ecx, DSTRIDE
    lea rdx, [rip+g_dice]
    mov dword ptr [rdx+rax+D_HELD], 0
    inc ecx
    cmp ecx, 6
    jb 1b
    ret

# refresh_dice : recalcule la pose de tous les dés au repos
refresh_dice:
    ENTER
    xor r12d, r12d
.Lrd:
    imul eax, r12d, DSTRIDE
    lea rdi, [rip+g_dice]
    add rdi, rax
    movsd xmm0, qword ptr [rip+k_one]
    call update_die
    inc r12d
    cmp r12d, 6
    jb .Lrd
    mov dword ptr [rip+g_dirty], 1
    LEAVE

# ---------- déroulement d'une partie ----------

new_game:
    ENTER
    mov dword ptr [rip+g_pot], POT_INIT
    mov dword ptr [rip+g_ptok], 0
    mov dword ptr [rip+g_btok], 0
    mov dword ptr [rip+g_starter], 0
    mov dword ptr [rip+g_round], 0
    call begin_round
    LEAVE

begin_round:
    ENTER
    inc dword ptr [rip+g_round]
    call clear_held
    call refresh_dice
    mov dword ptr [rip+g_lim], 3
    mov dword ptr [rip+g_pthrows], 0
    mov dword ptr [rip+g_bthrows], 0
    mov dword ptr [rip+g_target], 0
    lea rdi, [rip+g_line2]
    call msg_start
    cmp dword ptr [rip+g_starter], 0
    jne .Lbr_bot
    mov dword ptr [rip+g_phase], PH_PREROLL
    lea rdi, [rip+g_line1]
    call msg_start
    lea rsi, [rip+t_you_first]
    call msg_str
    jmp .Lbr_end
.Lbr_bot:
    mov dword ptr [rip+g_phase], PH_BOT
    lea rdi, [rip+g_line1]
    call msg_start
    lea rsi, [rip+t_bot_first]
    call msg_str
    mov dword ptr [rip+g_botmask], 0x38
    mov ecx, 1100
    mov edx, ACT_BOT_ROLL
    call set_wake
.Lbr_end:
    mov dword ptr [rip+g_dirty], 1
    LEAVE

# player_press_main : LANCER / RELANCER / SUIVANT / REJOUER selon la phase
player_press_main:
    ENTER
    mov eax, dword ptr [rip+g_phase]
    cmp eax, PH_PREROLL
    je .Lpm_pre
    cmp eax, PH_CHOOSE
    je .Lpm_choose
    cmp eax, PH_RESULT
    je .Lpm_next
    cmp eax, PH_OVER
    je .Lpm_new
    jmp .Lpm_end
.Lpm_pre:
    mov dword ptr [rip+g_who], 0
    mov dword ptr [rip+g_pthrows], 1
    mov dword ptr [rip+g_phase], PH_ROLLING
    lea rdi, [rip+g_line1]
    call msg_start
    lea rsi, [rip+t_rolling]
    call msg_str
    mov ecx, 7
    call start_throw
    jmp .Lpm_end
.Lpm_choose:
    xor ebx, ebx                    # masque des dés non gardés
    xor r12d, r12d
.Lpm_m:
    imul eax, r12d, DSTRIDE
    lea rsi, [rip+g_dice]
    cmp dword ptr [rsi+rax+D_HELD], 0
    jne 1f
    bts ebx, r12d
1:  inc r12d
    cmp r12d, 3
    jb .Lpm_m
    test ebx, ebx
    jnz 2f
    call finish_player_turn         # tout gardé : on valide
    jmp .Lpm_end
2:  call clear_held
    inc dword ptr [rip+g_pthrows]
    mov dword ptr [rip+g_who], 0
    mov dword ptr [rip+g_phase], PH_ROLLING
    lea rdi, [rip+g_line1]
    call msg_start
    lea rsi, [rip+t_rolling]
    call msg_str
    mov ecx, ebx
    call start_throw
    jmp .Lpm_end
.Lpm_next:
    call begin_round
    jmp .Lpm_end
.Lpm_new:
    call new_game
.Lpm_end:
    LEAVE

# player_press_second : VALIDER (garder la main actuelle)
player_press_second:
    cmp dword ptr [rip+g_phase], PH_CHOOSE
    jne 1f
    jmp finish_player_turn
1:  ret

# on_roll_done : appelé quand les dés se sont posés
on_roll_done:
    ENTER
    cmp dword ptr [rip+g_who], 0
    jne .Lrd_bot
    mov eax, dword ptr [rip+g_pthrows]
    cmp eax, dword ptr [rip+g_lim]
    jae .Lrd_fin
    mov dword ptr [rip+g_phase], PH_CHOOSE
    lea rdi, [rip+g_line1]
    call msg_start
    lea rsi, [rip+t_ch1]
    call msg_str
    mov eax, dword ptr [rip+g_pthrows]
    call msg_num
    lea rsi, [rip+t_slash]
    call msg_str
    mov eax, dword ptr [rip+g_lim]
    call msg_num
    lea rsi, [rip+t_ch2]
    call msg_str
    xor ecx, ecx
    call score_hand
    lea rdi, [rip+g_line2]
    call msg_start
    lea rsi, [rip+t_toi]
    call msg_str
    call msg_name
    jmp .Lrd_end
.Lrd_fin:
    call finish_player_turn
    jmp .Lrd_end
.Lrd_bot:
    call bot_after_roll
.Lrd_end:
    LEAVE

# finish_player_turn : ta main est figée
finish_player_turn:
    ENTER
    call clear_held
    call refresh_dice
    xor ecx, ecx
    call score_hand
    mov dword ptr [rip+g_prank], eax
    mov dword ptr [rip+g_ptokw], edx
    mov dword ptr [rip+g_pcat], ecx
    lea rdi, [rip+g_line2]
    call msg_start
    lea rsi, [rip+t_toi]
    call msg_str
    mov ecx, dword ptr [rip+g_pcat]
    call msg_name
    mov dword ptr [rip+g_phase], PH_BOT
    cmp dword ptr [rip+g_starter], 0
    jne .Lfp_second
    mov eax, dword ptr [rip+g_prank]
    mov dword ptr [rip+g_target], eax
    mov eax, dword ptr [rip+g_pthrows]
    mov dword ptr [rip+g_lim], eax
    mov dword ptr [rip+g_bthrows], 0
    mov dword ptr [rip+g_botmask], 0x38
    lea rdi, [rip+g_line1]
    call msg_start
    lea rsi, [rip+t_bp1]
    call msg_str
    mov eax, dword ptr [rip+g_lim]
    call msg_num
    lea rsi, [rip+t_bp2]
    call msg_str
    mov ecx, 900
    mov edx, ACT_BOT_ROLL
    call set_wake
    jmp .Lfp_end
.Lfp_second:
    mov ecx, 600
    mov edx, ACT_RESOLVE
    call set_wake
.Lfp_end:
    mov dword ptr [rip+g_dirty], 1
    LEAVE

# bot_after_roll : le bot regarde ses dés et décide de s'arrêter ou de relancer
bot_after_roll:
    ENTER
    inc dword ptr [rip+g_bthrows]
    mov ecx, 3
    call score_hand
    mov dword ptr [rip+g_brank], eax
    mov dword ptr [rip+g_btokw], edx
    mov dword ptr [rip+g_bcat], ecx
    mov r12d, eax
    lea rdi, [rip+g_line2]
    call msg_start
    lea rsi, [rip+t_bot]
    call msg_str
    mov ecx, dword ptr [rip+g_bcat]
    call msg_name
    mov eax, dword ptr [rip+g_bthrows]
    cmp eax, dword ptr [rip+g_lim]
    jae .Lbo_stop
    cmp r12d, 700
    jae .Lbo_stop
    mov edx, dword ptr [rip+g_target]
    test edx, edx
    jz 1f
    cmp r12d, edx
    ja .Lbo_stop
1:  xor ebx, ebx                    # il garde les as, un 2 et un 4
    xor r13d, r13d
    xor r14d, r14d
.Lbo_d:
    imul eax, r14d, DSTRIDE
    lea rsi, [rip+g_dice+3*DSTRIDE]
    mov r8d, dword ptr [rsi+rax+D_VAL]
    cmp r8d, 1
    je .Lbo_keep
    cmp r8d, 2
    jne 2f
    bts r13d, 0
    jnc .Lbo_keep
    jmp .Lbo_re
2:  cmp r8d, 4
    jne .Lbo_re
    bts r13d, 1
    jnc .Lbo_keep
.Lbo_re:
    bts ebx, r14d
.Lbo_keep:
    inc r14d
    cmp r14d, 3
    jb .Lbo_d
    test ebx, ebx
    jz .Lbo_stop
    popcnt r13d, ebx
    shl ebx, 3
    mov dword ptr [rip+g_botmask], ebx
    lea rdi, [rip+g_line1]
    call msg_start
    lea rsi, [rip+t_brel1]
    call msg_str
    mov eax, r13d
    call msg_num
    lea rsi, [rip+t_brel2]
    call msg_str
    mov ecx, 1000
    mov edx, ACT_BOT_ROLL
    call set_wake
    jmp .Lbo_end
.Lbo_stop:
    mov ecx, 900
    mov edx, ACT_BOT_DONE
    call set_wake
.Lbo_end:
    mov dword ptr [rip+g_dirty], 1
    LEAVE

# do_action : ecx = action programmée (set_wake) qui arrive à échéance
do_action:
    ENTER
    cmp ecx, ACT_BOT_ROLL
    je .Lda_roll
    cmp ecx, ACT_BOT_DONE
    je .Lda_done
    cmp ecx, ACT_RESOLVE
    je .Lda_res
    jmp .Lda_end
.Lda_roll:
    mov dword ptr [rip+g_who], 1
    mov dword ptr [rip+g_phase], PH_BOT
    cmp dword ptr [rip+g_bthrows], 0
    jne 1f
    lea rdi, [rip+g_line1]
    call msg_start
    lea rsi, [rip+t_bthrow]
    call msg_str
1:  mov ecx, dword ptr [rip+g_botmask]
    call start_throw
    jmp .Lda_end
.Lda_done:
    cmp dword ptr [rip+g_starter], 1
    jne .Lda_res
    mov eax, dword ptr [rip+g_bthrows]          # le bot commençait : à toi
    mov dword ptr [rip+g_lim], eax
    mov dword ptr [rip+g_pthrows], 0
    mov dword ptr [rip+g_phase], PH_PREROLL
    lea rdi, [rip+g_line1]
    call msg_start
    lea rsi, [rip+t_bst1]
    call msg_str
    mov eax, dword ptr [rip+g_bthrows]
    call msg_num
    lea rsi, [rip+t_bst2]
    call msg_str
    mov eax, dword ptr [rip+g_lim]
    call msg_num
    lea rsi, [rip+t_bst3]
    call msg_str
    mov dword ptr [rip+g_dirty], 1
    jmp .Lda_end
.Lda_res:
    call resolve_round
.Lda_end:
    LEAVE

# resolve_round : compare les deux mains et déplace les jetons
resolve_round:
    ENTER
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
    lea rdi, [rip+g_line2]
    call msg_start
    lea rsi, [rip+t_toi]
    call msg_str
    mov ecx, dword ptr [rip+g_pcat]
    call msg_name
    lea rsi, [rip+t_gap]
    call msg_str
    lea rsi, [rip+t_bot]
    call msg_str
    mov ecx, dword ptr [rip+g_bcat]
    call msg_name
    lea rdi, [rip+g_line1]
    call msg_start
    mov eax, dword ptr [rip+g_prank]
    cmp eax, dword ptr [rip+g_brank]
    je .Lrr_tie
    ja .Lrr_you
    mov edi, dword ptr [rip+g_btokw]            # le bot gagne la manche
    lea rsi, [rip+g_btok]
    lea rdx, [rip+g_ptok]
    call transfer
    mov r12d, eax
    mov dword ptr [rip+g_starter], 0
    lea rsi, [rip+t_losr]
    call msg_str
    mov eax, r12d
    call msg_num
    lea rsi, [rip+t_jet]
    call msg_str
    jmp .Lrr_check
.Lrr_you:
    mov edi, dword ptr [rip+g_ptokw]            # tu gagnes la manche
    lea rsi, [rip+g_ptok]
    lea rdx, [rip+g_btok]
    call transfer
    mov r12d, eax
    mov dword ptr [rip+g_starter], 1
    lea rsi, [rip+t_winr]
    call msg_str
    mov eax, r12d
    call msg_num
    lea rsi, [rip+t_jet]
    call msg_str
    jmp .Lrr_check
.Lrr_tie:
    lea rsi, [rip+t_tie]
    call msg_str
    mov dword ptr [rip+g_phase], PH_RESULT
    jmp .Lrr_end
.Lrr_check:
    mov dword ptr [rip+g_phase], PH_RESULT
    cmp dword ptr [rip+g_pot], 0
    jne .Lrr_end
    cmp dword ptr [rip+g_ptok], 0
    je .Lrr_win
    cmp dword ptr [rip+g_btok], 0
    je .Lrr_lose
    jmp .Lrr_end
.Lrr_win:
    lea rdi, [rip+g_line1]
    call msg_start
    lea rsi, [rip+t_victory]
    call msg_str
    mov dword ptr [rip+g_phase], PH_OVER
    jmp .Lrr_end
.Lrr_lose:
    lea rdi, [rip+g_line1]
    call msg_start
    lea rsi, [rip+t_defeat]
    call msg_str
    mov dword ptr [rip+g_phase], PH_OVER
.Lrr_end:
    mov dword ptr [rip+g_dirty], 1
    LEAVE

# ---------- clics ----------

# hit_button : ecx = x, edx = y (tampon), xmm0 = a, xmm1 = b  ->  eax = 1 si dans le bouton
hit_button:
    cvtsi2sd xmm2, ecx
    movsd qword ptr [rip+hb_px], xmm2
    cvtsi2sd xmm2, edx
    movsd qword ptr [rip+hb_py], xmm2
    movsd xmm2, qword ptr [rip+k_btntz]
    call scr_ground
    movsd xmm2, qword ptr [rip+hb_px]
    subsd xmm2, xmm0
    movsd xmm3, qword ptr [rip+hb_py]
    subsd xmm3, xmm1
    movsd xmm4, qword ptr [rip+k_btnr]
    mulsd xmm4, qword ptr [rip+g_s]
    divsd xmm2, xmm4
    mulsd xmm2, xmm2
    mulsd xmm4, qword ptr [rip+k_ysq]
    divsd xmm3, xmm4
    mulsd xmm3, xmm3
    addsd xmm2, xmm3
    xor eax, eax
    comisd xmm2, qword ptr [rip+k_one]
    ja 1f
    mov eax, 1
1:  ret

# on_click : ecx = x, edx = y (coordonnées du tampon)
on_click:
    ENTER
    inc dword ptr [rip+g_clicks]
    mov r12d, ecx
    mov r13d, edx
    mov dword ptr [rip+g_dist+8], ecx
    mov dword ptr [rip+g_dist+12], edx
    mov eax, dword ptr [rip+g_phase]
    cmp eax, PH_ROLLING
    je .Loc_end
    cmp eax, PH_BOT
    je .Loc_end
    mov ecx, r12d
    mov edx, r13d
    movsd xmm0, qword ptr [rip+k_btna]
    movsd xmm1, qword ptr [rip+k_btnbm]
    call hit_button
    test eax, eax
    jz 1f
    call player_press_main
    jmp .Loc_end
1:  mov ecx, r12d
    mov edx, r13d
    movsd xmm0, qword ptr [rip+k_btna]
    movsd xmm1, qword ptr [rip+k_btnbp]
    call hit_button
    test eax, eax
    jz 2f
    call player_press_second
    jmp .Loc_end
2:  cmp dword ptr [rip+g_phase], PH_CHOOSE
    jne .Loc_end
    xor r14d, r14d
.Loc_die:
    imul eax, r14d, DSTRIDE
    lea rbx, [rip+g_dice]
    add rbx, rax
    lea rsi, [rbx+D_P]
    lea rdi, [rip+g_pt1]
    call proj
    mov eax, dword ptr [rip+g_pt1]
    sub eax, r12d
    imul eax, eax
    mov ecx, dword ptr [rip+g_pt1+4]
    sub ecx, r13d
    imul ecx, ecx
    add eax, ecx
    lea rdx, [rip+g_dist]
    mov dword ptr [rdx+r14*4], eax
    cmp eax, 15625
    ja 3f
    xor dword ptr [rbx+D_HELD], 1
    inc dword ptr [rip+g_tog]
    mov rdi, rbx
    movsd xmm0, qword ptr [rip+k_one]
    call update_die
    mov dword ptr [rip+g_dirty], 1
    jmp .Loc_end
3:  inc r14d
    cmp r14d, 3
    jb .Loc_die
.Loc_end:
    LEAVE

# ---------- dessin : boutons, interface, image ----------

# draw_button : xmm0 = a, xmm1 = b, rsi = libellé, ecx = actif (0/1), edx = couleur (0 or, 1 bleu)
draw_button:
    ENTER
    movsd qword ptr [rip+bt_a], xmm0
    movsd qword ptr [rip+bt_b], xmm1
    mov r12, rsi
    test ecx, ecx
    jz .Ldb_gray
    test edx, edx
    jnz .Ldb_blue
    mov dword ptr [rip+g_ctop], C_BTNG
    mov dword ptr [rip+g_cside], C_BTNGS
    mov r13d, C_BTNTXT
    jmp .Ldb_draw
.Ldb_blue:
    mov dword ptr [rip+g_ctop], C_BTNB
    mov dword ptr [rip+g_cside], C_BTNBS
    mov r13d, C_BTNTXT
    jmp .Ldb_draw
.Ldb_gray:
    mov dword ptr [rip+g_ctop], C_BTNX
    mov dword ptr [rip+g_cside], C_BTNXS
    mov r13d, C_BTNTXTX
.Ldb_draw:
    movsd xmm0, qword ptr [rip+bt_a]
    movsd xmm1, qword ptr [rip+bt_b]
    movsd xmm2, qword ptr [rip+k_felt]
    movsd xmm3, qword ptr [rip+k_btnr]
    movsd xmm4, qword ptr [rip+k_btnh]
    call draw_cylinder
    mov rcx, qword ptr [rip+g_fontB]
    call sel_font
    mov ecx, r13d
    call set_txt
    movsd xmm0, qword ptr [rip+k_btntz]
    movsd qword ptr [rip+g_gtz], xmm0
    movsd xmm0, qword ptr [rip+bt_a]
    movsd xmm1, qword ptr [rip+bt_b]
    subsd xmm1, qword ptr [rip+k_btnoff]
    mov rsi, r12
    call draw_ground_text
    movsd xmm0, qword ptr [rip+k_felt]
    movsd qword ptr [rip+g_gtz], xmm0
    LEAVE

draw_buttons:
    ENTER
    mov eax, dword ptr [rip+g_phase]
    lea rsi, [rip+b_dots]
    xor ecx, ecx
    cmp eax, PH_PREROLL
    jne 1f
    lea rsi, [rip+b_lancer]
    mov ecx, 1
1:  cmp eax, PH_CHOOSE
    jne 2f
    lea rsi, [rip+b_relancer]
    mov ecx, 1
2:  cmp eax, PH_RESULT
    jne 3f
    lea rsi, [rip+b_suivant]
    mov ecx, 1
3:  cmp eax, PH_OVER
    jne 4f
    lea rsi, [rip+b_rejouer]
    mov ecx, 1
4:  xor edx, edx
    movsd xmm0, qword ptr [rip+k_btna]
    movsd xmm1, qword ptr [rip+k_btnbm]
    call draw_button
    xor ecx, ecx
    cmp dword ptr [rip+g_phase], PH_CHOOSE
    sete cl
    lea rsi, [rip+b_valider]
    mov edx, 1
    movsd xmm0, qword ptr [rip+k_btna]
    movsd xmm1, qword ptr [rip+k_btnbp]
    call draw_button
    LEAVE

# draw_hud : titre, numéro de manche, messages
draw_hud:
    ENTER
    mov rcx, qword ptr [rip+g_fontH]
    call sel_font
    mov ecx, C_GOLD
    call set_txt
    mov ecx, 40
    mov edx, 6
    lea r8, [rip+s_h1]
    xor r9d, r9d
    call draw_flat
    mov rcx, qword ptr [rip+g_fontM]
    call sel_font
    mov ecx, C_WHITE
    call set_txt
    lea rdi, [rip+g_lbl]
    call msg_start
    lea rsi, [rip+t_manche]
    call msg_str
    mov eax, dword ptr [rip+g_round]
    call msg_num
    mov ecx, BUFW-40
    mov edx, 34
    lea r8, [rip+g_lbl]
    mov r9d, 2                      # TA_RIGHT
    call draw_flat
    mov ecx, 40
    mov edx, 124
    lea r8, [rip+g_line1]
    xor r9d, r9d
    call draw_flat
    mov ecx, C_GOLD
    call set_txt
    mov ecx, 40
    mov edx, 196
    lea r8, [rip+g_line2]
    xor r9d, r9d
    call draw_flat
    LEAVE

# render_frame : dessine toute la scène puis réduit le tampon vers la fenêtre
render_frame:
    ENTER
    mov ecx, C_BG
    call set_brush
    call pen_off
    mov rcx, qword ptr [rip+g_hdc]
    xor edx, edx
    xor r8d, r8d
    mov r9d, BUFW
    mov dword ptr [rsp+32], BUFH
    mov dword ptr [rsp+40], 0x00F00021      # PATCOPY
    call PatBlt
    call draw_table
    # étiquettes sur le tapis, avec les nombres de jetons
    mov rcx, qword ptr [rip+g_fontG]
    call sel_font
    mov ecx, C_TXTGND
    call set_txt
    lea rdi, [rip+g_lbl]
    call msg_start
    lea rsi, [rip+l_pot]
    call msg_str
    mov eax, dword ptr [rip+g_pot]
    call msg_num
    lea rsi, [rip+g_lbl]
    movsd xmm0, qword ptr [rip+k_pota]
    movsd xmm1, qword ptr [rip+k_potlz]
    call draw_ground_text
    lea rdi, [rip+g_lbl]
    call msg_start
    lea rsi, [rip+l_toi]
    call msg_str
    mov eax, dword ptr [rip+g_ptok]
    call msg_num
    lea rsi, [rip+g_lbl]
    xorpd xmm0, xmm0
    movsd xmm1, qword ptr [rip+k_toilz]
    call draw_ground_text
    lea rdi, [rip+g_lbl]
    call msg_start
    lea rsi, [rip+l_bot]
    call msg_str
    mov eax, dword ptr [rip+g_btok]
    call msg_num
    lea rsi, [rip+g_lbl]
    xorpd xmm0, xmm0
    movsd xmm1, qword ptr [rip+k_botlz]
    call draw_ground_text
    # jetons (du plus loin au plus près), dés, boutons
    mov dword ptr [rip+g_ctop], C_BOTTOP
    mov dword ptr [rip+g_cside], C_BOTSIDE
    xorpd xmm0, xmm0
    movsd xmm1, qword ptr [rip+k_botz]
    mov edi, dword ptr [rip+g_btok]
    call draw_chips
    mov dword ptr [rip+g_ctop], C_POTTOP
    mov dword ptr [rip+g_cside], C_POTSIDE
    movsd xmm0, qword ptr [rip+k_pota]
    xorpd xmm1, xmm1
    mov edi, dword ptr [rip+g_pot]
    call draw_chips
    call draw_buttons
    call draw_dice_all
    mov dword ptr [rip+g_ctop], C_PLTOP
    mov dword ptr [rip+g_cside], C_PLSIDE
    xorpd xmm0, xmm0
    movsd xmm1, qword ptr [rip+k_plz]
    mov edi, dword ptr [rip+g_ptok]
    call draw_chips
    call draw_hud
    call GdiFlush
    call downsample
    mov dword ptr [rip+g_dirty], 0
    LEAVE

t_sp:       .asciz " "
.bss
g_dbg:      .skip 96
g_clicks:   .skip 4
g_tog:      .skip 4
g_dist:     .skip 16
.text

# debug_title : écrit les valeurs des six dés et la phase dans le titre de la fenêtre
debug_title:
    ENTER
    lea rdi, [rip+g_dbg]
    call msg_start
    xor r12d, r12d
.Ldt:
    imul eax, r12d, DSTRIDE
    lea rsi, [rip+g_dice]
    mov eax, dword ptr [rsi+rax+D_VAL]
    call msg_num
    lea rsi, [rip+t_sp]
    call msg_str
    inc r12d
    cmp r12d, 6
    jb .Ldt
    mov eax, dword ptr [rip+g_phase]
    call msg_num
    lea rsi, [rip+t_sp]
    call msg_str
    mov eax, dword ptr [rip+g_who]
    call msg_num
    lea rsi, [rip+t_sp]
    call msg_str
    mov eax, dword ptr [rip+g_pthrows]
    call msg_num
    lea rsi, [rip+t_sp]
    call msg_str
    mov eax, dword ptr [rip+g_lim]
    call msg_num
    lea rsi, [rip+t_sp]
    call msg_str
    mov eax, dword ptr [rip+g_starter]
    call msg_num
    lea rsi, [rip+t_sp]
    call msg_str
    mov eax, dword ptr [rip+g_dice+D_HELD]
    add eax, eax
    add eax, dword ptr [rip+g_dice+DSTRIDE+D_HELD]
    add eax, eax
    add eax, dword ptr [rip+g_dice+2*DSTRIDE+D_HELD]
    call msg_num
    lea rsi, [rip+t_sp]
    call msg_str
    mov eax, dword ptr [rip+g_clicks]
    call msg_num
    lea rsi, [rip+t_sp]
    call msg_str
    mov eax, dword ptr [rip+g_dist]
    call msg_num
    lea rsi, [rip+t_sp]
    call msg_str
    mov eax, dword ptr [rip+g_dist+4]
    call msg_num
    lea rsi, [rip+t_sp]
    call msg_str
    mov eax, dword ptr [rip+g_dist+8]
    call msg_num
    lea rsi, [rip+t_sp]
    call msg_str
    mov eax, dword ptr [rip+g_dist+12]
    call msg_num
    lea rsi, [rip+t_sp]
    call msg_str
    mov eax, dword ptr [rip+g_pt1+4]
    call msg_num
    mov rcx, qword ptr [rip+g_hwnd]
    lea rdx, [rip+g_dbg]
    call SetWindowTextA
    LEAVE
