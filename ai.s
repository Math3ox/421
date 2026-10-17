# ============================================================
#  ai.s — niveaux du bot, calcul de probabilités, aide, réglages (inclus par 421.s)
#
#  - facile    : stratégie « normale » mais 35 % de décisions au hasard
#  - normal    : garde les as, un 2 et un 4 ; s'arrête dès qu'il bat le 1er joueur
#  - difficile : stratégie optimale (utilité en jetons) par programmation dynamique :
#       premier joueur : tables W/VS précalculées (aitab.s, générées par gen_tables.py) ;
#       second joueur  : calcul exact à la volée contre la combinaison à battre (1 ou 2 relances).
#  Les états sont les 56 mains triées ; tbl_sid donne l'indice d'une main (a,b,c) non triée.
# ============================================================

.section .rdata,"dr"
.balign 4
k_eps:      .float 0.000001
lv_0:       .asciz "facile"
lv_1:       .asciz "normal"
lv_2:       .asciz "difficile"
.balign 8
lv_names:   .quad lv_0, lv_1, lv_2

.data
.balign 4
g_level:    .long 1                 # 0 facile, 1 normal, 2 difficile

.bss
.balign 16
pb_v:       .skip 16                # les 3 dés étudiés
g_best:     .skip 4
st_421:     .skip 4
st_better:  .skip 4
st_total:   .skip 4
st_cur:     .skip 4
.balign 16
hv0:        .skip 224               # valeur de s'arrêter (56 mains), contre la cible courante
hv1:        .skip 224               # valeur avec 1 relance restante

.include "aitab.s"

.text

# load_hand : ecx = premier dé de la main (0 ou 3) -> pb_v
load_hand:
    imul eax, ecx, DSTRIDE
    lea rdx, [rip+g_dice]
    add rdx, rax
    mov eax, dword ptr [rdx+D_VAL]
    mov dword ptr [rip+pb_v], eax
    mov eax, dword ptr [rdx+DSTRIDE+D_VAL]
    mov dword ptr [rip+pb_v+4], eax
    mov eax, dword ptr [rdx+2*DSTRIDE+D_VAL]
    mov dword ptr [rip+pb_v+8], eax
    ret

# enum_mean : ecx = masque des dés relancés (bits 0-2), rdx = table de 56 floats, pb_v = les dés.
#             -> xmm0 = moyenne de la table sur les 6^k résultats (masque 0 : valeur de la main actuelle)
enum_mean:
    push r12
    push r13
    push r14
    push r15
    mov r11, rdx
    mov r8d, 1
    test cl, 1
    jz 1f
    imul r8d, r8d, 6
1:  test cl, 2
    jz 2f
    imul r8d, r8d, 6
2:  test cl, 4
    jz 3f
    imul r8d, r8d, 6
3:  mov r15d, 6
    xorps xmm0, xmm0
    xor r10d, r10d
.Lem_n:
    mov r12d, dword ptr [rip+pb_v]
    mov r13d, dword ptr [rip+pb_v+4]
    mov r14d, dword ptr [rip+pb_v+8]
    mov eax, r10d
    test cl, 1
    jz 4f
    xor edx, edx
    div r15d
    lea r12d, [rdx+1]
4:  test cl, 2
    jz 5f
    xor edx, edx
    div r15d
    lea r13d, [rdx+1]
5:  test cl, 4
    jz 6f
    xor edx, edx
    div r15d
    lea r14d, [rdx+1]
6:  lea eax, [r12-1]
    imul eax, eax, 6
    lea edx, [r13-1]
    add eax, edx
    imul eax, eax, 6
    lea edx, [r14-1]
    add eax, edx
    lea rdx, [rip+tbl_sid]
    movzx eax, byte ptr [rdx+rax]
    addss xmm0, dword ptr [r11+rax*4]
    inc r10d
    cmp r10d, r8d
    jb .Lem_n
    cvtsi2ss xmm1, r8d
    divss xmm0, xmm1
    pop r15
    pop r14
    pop r13
    pop r12
    ret

# enum_stats : ecx = masque, pb_v = les dés -> st_421, st_better (rang > rang actuel), st_total, st_cur
enum_stats:
    push rbx
    push rsi
    push rdi
    push r12
    push r13
    push r14
    push r15
    mov edi, ecx
    mov r8d, dword ptr [rip+pb_v]
    mov r9d, dword ptr [rip+pb_v+4]
    mov r10d, dword ptr [rip+pb_v+8]
    call rank3
    mov dword ptr [rip+st_cur], eax
    mov dword ptr [rip+st_421], 0
    mov dword ptr [rip+st_better], 0
    mov ebx, 1
    test dil, 1
    jz 1f
    imul ebx, ebx, 6
1:  test dil, 2
    jz 2f
    imul ebx, ebx, 6
2:  test dil, 4
    jz 3f
    imul ebx, ebx, 6
3:  mov dword ptr [rip+st_total], ebx
    mov r15d, 6
    xor esi, esi
.Les_n:
    mov r12d, dword ptr [rip+pb_v]
    mov r13d, dword ptr [rip+pb_v+4]
    mov r14d, dword ptr [rip+pb_v+8]
    mov eax, esi
    test dil, 1
    jz 4f
    xor edx, edx
    div r15d
    lea r12d, [rdx+1]
4:  test dil, 2
    jz 5f
    xor edx, edx
    div r15d
    lea r13d, [rdx+1]
5:  test dil, 4
    jz 6f
    xor edx, edx
    div r15d
    lea r14d, [rdx+1]
6:  mov r8d, r12d
    mov r9d, r13d
    mov r10d, r14d
    call rank3
    cmp eax, 1000
    jne 7f
    inc dword ptr [rip+st_421]
7:  cmp eax, dword ptr [rip+st_cur]
    jle 8f
    inc dword ptr [rip+st_better]
8:  inc esi
    cmp esi, ebx
    jb .Les_n
    pop r15
    pop r14
    pop r13
    pop r12
    pop rdi
    pop rsi
    pop rbx
    ret

# build_v0 : hv0[i] = valeur de s'arrêter avec la main i contre la cible (g_target / g_targettok)
build_v0:
    ENTER
    xor r12d, r12d
.Lbv0:
    lea eax, [r12+r12*2]
    lea rdx, [rip+tbl_h56]
    movzx r8d, byte ptr [rdx+rax]
    movzx r9d, byte ptr [rdx+rax+1]
    movzx r10d, byte ptr [rdx+rax+2]
    call rank3
    cmp eax, dword ptr [rip+g_target]
    ja 1f
    je 2f
    mov edx, dword ptr [rip+g_targettok]
    neg edx
    jmp 1f
2:  xor edx, edx
1:  cvtsi2ss xmm0, edx
    lea rdx, [rip+hv0]
    movss dword ptr [rdx+r12*4], xmm0
    inc r12d
    cmp r12d, 56
    jb .Lbv0
    LEAVE

# build_v1 : hv1[i] = meilleure valeur avec au plus 1 relance
build_v1:
    ENTER
    xor r12d, r12d
.Lbv1:
    lea eax, [r12+r12*2]
    lea rdx, [rip+tbl_h56]
    movzx ecx, byte ptr [rdx+rax]
    mov dword ptr [rip+pb_v], ecx
    movzx ecx, byte ptr [rdx+rax+1]
    mov dword ptr [rip+pb_v+4], ecx
    movzx ecx, byte ptr [rdx+rax+2]
    mov dword ptr [rip+pb_v+8], ecx
    lea rdx, [rip+hv0]
    movss xmm0, dword ptr [rdx+r12*4]
    movss dword ptr [rip+g_best], xmm0
    mov ebx, 1
.Lbv1m:
    mov ecx, ebx
    lea rdx, [rip+hv0]
    call enum_mean
    comiss xmm0, dword ptr [rip+g_best]
    jbe 1f
    movss dword ptr [rip+g_best], xmm0
1:  inc ebx
    cmp ebx, 8
    jb .Lbv1m
    movss xmm0, dword ptr [rip+g_best]
    lea rdx, [rip+hv1]
    movss dword ptr [rdx+r12*4], xmm0
    inc r12d
    cmp r12d, 56
    jb .Lbv1
    LEAVE

# hard_choose : ecx = premier dé de la main (0 ou 3), edx = lancers déjà faits
#               ([g_lim], [g_target], [g_targettok] décrivent la manche) -> eax = masque (0 = s'arrêter)
hard_choose:
    ENTER
    mov r12d, ecx
    mov r13d, edx
    xor r14d, r14d
    mov eax, dword ptr [rip+g_lim]
    cmp r13d, eax
    jae .Lhc_end
    cmp dword ptr [rip+g_target], 0
    jne .Lhc_foll
    mov ecx, r12d                           # --- premier joueur ---
    call load_hand
    lea r15, [rip+tbl_W]
    lea eax, [r13-1]
    imul eax, eax, 224
    lea rsi, [r15+rax]                      # valeur de s'arrêter après t lancers
    cmp r13d, 1
    jne 1f
    lea rdi, [r15+672]                      # puis la valeur de continuer (VS2)
    jmp 2f
1:  lea rdi, [r15+448]                      # (W3)
2:  xor ecx, ecx
    mov rdx, rsi
    call enum_mean
    movss dword ptr [rip+g_best], xmm0
    mov ebx, 1
.Lhc_s:
    mov ecx, ebx
    mov rdx, rdi
    call enum_mean
    movss xmm1, dword ptr [rip+g_best]
    addss xmm1, dword ptr [rip+k_eps]
    comiss xmm0, xmm1
    jbe 3f
    movss dword ptr [rip+g_best], xmm0
    mov r14d, ebx
3:  inc ebx
    cmp ebx, 8
    jb .Lhc_s
    jmp .Lhc_end
.Lhc_foll:                                  # --- second joueur : calcul exact ---
    call build_v0
    mov r15d, dword ptr [rip+g_lim]
    sub r15d, r13d                          # relances restantes (1 ou 2)
    lea rdi, [rip+hv0]
    cmp r15d, 2
    jb 1f
    call build_v1
    lea rdi, [rip+hv1]
1:  mov ecx, r12d
    call load_hand
    xor ecx, ecx
    lea rdx, [rip+hv0]
    call enum_mean
    movss dword ptr [rip+g_best], xmm0
    mov ebx, 1
.Lhc_f:
    mov ecx, ebx
    mov rdx, rdi
    call enum_mean
    movss xmm1, dword ptr [rip+g_best]
    addss xmm1, dword ptr [rip+k_eps]
    comiss xmm0, xmm1
    jbe 2f
    movss dword ptr [rip+g_best], xmm0
    mov r14d, ebx
2:  inc ebx
    cmp ebx, 8
    jb .Lhc_f
.Lhc_end:
    mov eax, r14d
    LEAVE

# normal_choose : -> eax = masque (dés 3..5 du bot), 0 = il s'arrête
normal_choose:
    ENTER
    mov ecx, 3
    call score_hand
    mov r12d, eax
    cmp r12d, 700
    jae .Lnc_zero
    mov edx, dword ptr [rip+g_target]
    test edx, edx
    jz 1f
    cmp r12d, edx
    ja .Lnc_zero
1:  xor ebx, ebx                            # il garde les as, un 2 et un 4
    xor r13d, r13d
    xor r14d, r14d
.Lnc_d:
    imul eax, r14d, DSTRIDE
    lea rsi, [rip+g_dice+3*DSTRIDE]
    mov r8d, dword ptr [rsi+rax+D_VAL]
    cmp r8d, 1
    je .Lnc_keep
    cmp r8d, 2
    jne 2f
    bts r13d, 0
    jnc .Lnc_keep
    jmp .Lnc_re
2:  cmp r8d, 4
    jne .Lnc_re
    bts r13d, 1
    jnc .Lnc_keep
.Lnc_re:
    bts ebx, r14d
.Lnc_keep:
    inc r14d
    cmp r14d, 3
    jb .Lnc_d
    mov eax, ebx
    jmp .Lnc_end
.Lnc_zero:
    xor eax, eax
.Lnc_end:
    LEAVE

# bot_choose : décision du bot selon son niveau -> eax = masque (bits 0-2), 0 = s'arrête
bot_choose:
    ENTER
    cmp dword ptr [rip+g_level], 2
    jne 1f
    mov ecx, 3
    mov edx, dword ptr [rip+g_bthrows]
    call hard_choose
    jmp .Lbc_end
1:  cmp dword ptr [rip+g_level], 0
    jne .Lbc_normal
    call rng_next                           # facile : 35 % de décisions au hasard
    xor edx, edx
    mov ecx, 100
    div ecx
    cmp edx, 35
    jae .Lbc_normal
    call rng_next
    test al, 1
    jnz 2f
    xor eax, eax
    jmp .Lbc_end
2:  call rng_next
    xor edx, edx
    mov ecx, 7
    div ecx
    lea eax, [rdx+1]
    jmp .Lbc_end
.Lbc_normal:
    call normal_choose
.Lbc_end:
    LEAVE

# help_advice : touche H. Probabilités de la sélection courante + conseil de la stratégie optimale
help_advice:
    ENTER
    cmp dword ptr [rip+g_phase], PH_CHOOSE
    jne .Lha_end
    mov eax, dword ptr [rip+g_cur]
    lea r12d, [rax+rax*2]                   # premier dé du joueur
    lea rdx, [rip+g_pthrows]
    mov r13d, dword ptr [rdx+rax*4]         # lancers déjà faits
    xor r14d, r14d                          # sélection (dés à relancer)
    xor ebx, ebx
.Lha_sel:
    lea eax, [r12+rbx]
    imul eax, eax, DSTRIDE
    lea rdx, [rip+g_dice]
    cmp dword ptr [rdx+rax+D_HELD], 0
    je 1f
    bts r14d, ebx
1:  inc ebx
    cmp ebx, 3
    jb .Lha_sel
    mov ecx, r12d
    mov edx, r13d
    call hard_choose
    mov r15d, eax                           # conseil
    lea rdi, [rip+g_line2]
    call msg_start
    test r14d, r14d
    jz .Lha_adv
    mov ecx, r12d
    call load_hand
    mov ecx, r14d
    call enum_stats
    lea rsi, [rip+t_sel1]
    call msg_str
    mov eax, dword ptr [rip+st_421]
    imul eax, eax, 100
    mov ecx, dword ptr [rip+st_total]
    mov edx, ecx
    shr edx, 1
    add eax, edx
    xor edx, edx
    div ecx
    call msg_num
    lea rsi, [rip+t_sel2]
    call msg_str
    mov eax, dword ptr [rip+st_better]
    imul eax, eax, 100
    mov ecx, dword ptr [rip+st_total]
    mov edx, ecx
    shr edx, 1
    add eax, edx
    xor edx, edx
    div ecx
    call msg_num
    lea rsi, [rip+t_sel3]
    call msg_str
.Lha_adv:
    lea rsi, [rip+t_adv]
    call msg_str
    test r15d, r15d
    jnz 2f
    lea rsi, [rip+t_adv_keep]
    call msg_str
    jmp .Lha_done
2:  lea rsi, [rip+t_adv_re]
    call msg_str
    xor ebx, ebx
.Lha_d:
    bt r15d, ebx
    jnc 3f
    lea eax, [rbx+1]
    call msg_num
    lea rsi, [rip+t_sp]
    call msg_str
3:  inc ebx
    cmp ebx, 3
    jb .Lha_d
.Lha_done:
    mov dword ptr [rip+g_full], 1
    mov dword ptr [rip+g_dirty], 1
.Lha_end:
    LEAVE

# ---------- réglages au clavier ----------

# toggle_twop : touche J. 1 joueur contre le bot <-> 2 joueurs sur le même PC (nouvelle partie)
toggle_twop:
    ENTER
    xor dword ptr [rip+g_twop], 1
    call new_game
    call opt_save
    LEAVE

# cycle_level : touche L. Niveau du bot : facile -> normal -> difficile
cycle_level:
    ENTER
    mov eax, dword ptr [rip+g_level]
    inc eax
    cmp eax, 3
    jb 1f
    xor eax, eax
1:  mov dword ptr [rip+g_level], eax
    lea rdi, [rip+g_line2]
    call msg_start
    lea rsi, [rip+t_lvl]
    call msg_str
    lea rdx, [rip+lv_names]
    mov eax, dword ptr [rip+g_level]
    mov rsi, qword ptr [rdx+rax*8]
    call msg_str
    mov dword ptr [rip+g_full], 1
    mov dword ptr [rip+g_dirty], 1
    call opt_save
    LEAVE

# cycle_pot : touche P. Pot de départ 7 -> 11 -> 15 -> 21 (effet à la prochaine partie)
cycle_pot:
    ENTER
    mov eax, dword ptr [rip+g_potinit]
    mov ecx, 11
    cmp eax, 7
    je 1f
    mov ecx, 15
    cmp eax, 11
    je 1f
    mov ecx, 21
    cmp eax, 15
    je 1f
    mov ecx, 7
1:  mov dword ptr [rip+g_potinit], ecx
    lea rdi, [rip+g_line2]
    call msg_start
    lea rsi, [rip+t_potm1]
    call msg_str
    mov eax, dword ptr [rip+g_potinit]
    call msg_num
    lea rsi, [rip+t_potm2]
    call msg_str
    mov dword ptr [rip+g_full], 1
    mov dword ptr [rip+g_dirty], 1
    call opt_save
    LEAVE

# ---------- réglages mémorisés : 421.cfg à côté de l'exécutable (32 octets, aucun autre fichier) ----------
# champs : magie, mode de rendu (0 = auto, 1-4), pot de départ, niveau du bot, 2 joueurs, plein écran, victoires, défaites
.equ CFG_MAGIC1, 0x01313234             # "421" + version 1 (32 octets)
.equ CFG_MAGIC, 0x02313234              # version 2 (64 octets : + dernière adresse IP)

.data
.balign 4
g_optmode:  .long 0
g_optfs:    .long 0
.bss
.balign 8
g_cfgpath:  .skip 272
g_cfg:      .skip 64
.text

# opt_path : g_cfgpath = chemin de l'exécutable avec l'extension remplacée par .cfg
opt_path:
    ENTER
    xor ecx, ecx
    lea rdx, [rip+g_cfgpath]
    mov r8d, 260
    call GetModuleFileNameA
    lea rdx, [rip+g_cfgpath]
    mov ecx, eax
1:  test ecx, ecx
    jz 2f
    dec ecx
    cmp byte ptr [rdx+rcx], 46              # '.'
    jne 1b
    mov dword ptr [rdx+rcx+1], 0x00676663   # "cfg"
    jmp 3f
2:  mov byte ptr [rdx], 0                   # chemin introuvable : pas de sauvegarde
3:  LEAVE

# opt_load : lit 421.cfg s'il existe et valide chaque champ (sinon valeurs par défaut)
opt_load:
    ENTER
    call opt_path
    cmp byte ptr [rip+g_cfgpath], 0
    je .Lol_end
    lea rcx, [rip+g_cfgpath]
    mov edx, 0x80000000                     # GENERIC_READ
    mov r8d, 1                              # FILE_SHARE_READ
    xor r9d, r9d
    mov dword ptr [rsp+32], 3               # OPEN_EXISTING
    mov dword ptr [rsp+40], 0x80
    mov qword ptr [rsp+48], 0
    call CreateFileA
    cmp rax, -1
    je .Lol_end
    mov rbx, rax
    mov dword ptr [rip+g_written], 0
    mov rcx, rbx
    lea rdx, [rip+g_cfg]
    mov r8d, 64
    lea r9, [rip+g_written]
    mov qword ptr [rsp+32], 0
    call ReadFile
    mov rcx, rbx
    call CloseHandle
    cmp dword ptr [rip+g_written], 32
    jb .Lol_end
    mov eax, dword ptr [rip+g_cfg]
    cmp eax, CFG_MAGIC1
    je .Lol_fields
    cmp eax, CFG_MAGIC
    jne .Lol_end
    cmp dword ptr [rip+g_written], 64
    jb .Lol_end
    lea rsi, [rip+g_cfg+32]                 # dernière adresse IP saisie
    lea rdi, [rip+ns_ip]
    mov ecx, 4
    cld
    rep movsq
    mov byte ptr [rip+ns_ip+31], 0
    xor eax, eax
    lea rdx, [rip+ns_ip]
.Lol_len:
    cmp byte ptr [rdx+rax], 0
    je .Lol_lend
    inc eax
    cmp eax, 21
    jb .Lol_len
    mov byte ptr [rdx+rax], 0
.Lol_lend:
    mov dword ptr [rip+ns_iplen], eax
.Lol_fields:
    mov eax, dword ptr [rip+g_cfg+4]
    cmp eax, 4
    ja 1f
    mov dword ptr [rip+g_optmode], eax
1:  mov eax, dword ptr [rip+g_cfg+8]
    cmp eax, 7
    je 2f
    cmp eax, 11
    je 2f
    cmp eax, 15
    je 2f
    cmp eax, 21
    jne 3f
2:  mov dword ptr [rip+g_potinit], eax
3:  mov eax, dword ptr [rip+g_cfg+12]
    cmp eax, 2
    ja 4f
    mov dword ptr [rip+g_level], eax
4:  mov eax, dword ptr [rip+g_cfg+16]
    cmp eax, 1
    ja 5f
    mov dword ptr [rip+g_twop], eax
5:  mov eax, dword ptr [rip+g_cfg+20]
    cmp eax, 1
    ja 6f
    mov dword ptr [rip+g_optfs], eax
6:  mov eax, dword ptr [rip+g_cfg+24]
    cmp eax, 99999
    ja 7f
    mov dword ptr [rip+g_wins], eax
7:  mov eax, dword ptr [rip+g_cfg+28]
    cmp eax, 99999
    ja .Lol_end
    mov dword ptr [rip+g_losses], eax
.Lol_end:
    LEAVE

# opt_save : écrit les réglages courants dans 421.cfg (silencieux si le dossier n'est pas inscriptible)
opt_save:
    ENTER
    cmp byte ptr [rip+g_cfgpath], 0
    jne 1f
    call opt_path
    cmp byte ptr [rip+g_cfgpath], 0
    je .Los_end
1:  lea rdi, [rip+g_cfg]
    mov dword ptr [rdi], CFG_MAGIC
    xor eax, eax                            # mode : 0 = automatique
    cmp dword ptr [rip+g_auto], 0
    je 2f
    jmp 3f
2:  mov eax, dword ptr [rip+g_mode]
    inc eax
3:  mov dword ptr [rdi+4], eax
    mov eax, dword ptr [rip+g_potinit]
    mov dword ptr [rdi+8], eax
    mov eax, dword ptr [rip+g_level]
    mov dword ptr [rdi+12], eax
    mov eax, dword ptr [rip+g_twop]
    cmp eax, 2                              # le mode en ligne n'est pas mémorisé
    jne 1f
    mov eax, dword ptr [rip+g_prevtwop]
1:  mov dword ptr [rdi+16], eax
    mov eax, dword ptr [rip+g_fsmode]
    mov dword ptr [rdi+20], eax
    mov eax, dword ptr [rip+g_wins]
    mov dword ptr [rdi+24], eax
    mov eax, dword ptr [rip+g_losses]
    mov dword ptr [rdi+28], eax
    lea rsi, [rip+ns_ip]                    # dernière adresse IP
    lea rdi, [rip+g_cfg+32]
    mov ecx, 4
    cld
    rep movsq
    lea rcx, [rip+g_cfgpath]
    mov edx, 0x40000000                     # GENERIC_WRITE
    xor r8d, r8d
    xor r9d, r9d
    mov dword ptr [rsp+32], 2               # CREATE_ALWAYS
    mov dword ptr [rsp+40], 0x80
    mov qword ptr [rsp+48], 0
    call CreateFileA
    cmp rax, -1
    je .Los_end
    mov rbx, rax
    mov rcx, rbx
    lea rdx, [rip+g_cfg]
    mov r8d, 64
    lea r9, [rip+g_written]
    mov qword ptr [rsp+32], 0
    call WriteFile
    mov rcx, rbx
    call CloseHandle
.Los_end:
    LEAVE

.ifdef DEVTOOLS
# ---------- test : décisions du bot pour 26 situations x 216 mains (touche T -> 421_bot.bin) ----------
.section .rdata,"dr"
.balign 4
bt_name: .asciz "421_bot.bin"
bt_sc:
    .long 0, 0, 1, 3
    .long 0, 0, 2, 3
    .long 1000, 8, 1, 2
    .long 1000, 8, 1, 3
    .long 1000, 8, 2, 3
    .long 900, 7, 1, 2
    .long 900, 7, 1, 3
    .long 900, 7, 2, 3
    .long 813, 6, 1, 2
    .long 813, 6, 1, 3
    .long 813, 6, 2, 3
    .long 806, 3, 1, 2
    .long 806, 3, 1, 3
    .long 806, 3, 2, 3
    .long 706, 2, 1, 2
    .long 706, 2, 1, 3
    .long 706, 2, 2, 3
    .long 665, 1, 1, 2
    .long 665, 1, 1, 3
    .long 665, 1, 2, 3
    .long 541, 1, 1, 2
    .long 541, 1, 1, 3
    .long 541, 1, 2, 3
    .long 1, 1, 1, 2
    .long 1, 1, 1, 3
    .long 1, 1, 2, 3
.equ BT_N, 26
.bss
bt_out: .skip 4096
.text

bot_dump:
    ENTER
    xor r12d, r12d                          # scénario
    lea r14, [rip+bt_out]
.Lbd_sc:
    lea rax, [rip+bt_sc]
    mov ecx, r12d
    shl ecx, 4
    mov edx, dword ptr [rax+rcx]
    mov dword ptr [rip+g_target], edx
    mov edx, dword ptr [rax+rcx+4]
    mov dword ptr [rip+g_targettok], edx
    mov r15d, dword ptr [rax+rcx+8]         # lancers faits
    mov edx, dword ptr [rax+rcx+12]
    mov dword ptr [rip+g_lim], edx
    xor r13d, r13d                          # main 0..215
.Lbd_h:
    mov eax, r13d
    xor edx, edx
    mov ecx, 36
    div ecx
    inc eax
    mov dword ptr [rip+g_dice+3*DSTRIDE+D_VAL], eax
    mov eax, edx
    xor edx, edx
    mov ecx, 6
    div ecx
    inc eax
    inc edx
    mov dword ptr [rip+g_dice+4*DSTRIDE+D_VAL], eax
    mov dword ptr [rip+g_dice+5*DSTRIDE+D_VAL], edx
    mov ecx, 3
    mov edx, r15d
    call hard_choose
    mov rdx, r14
    mov byte ptr [rdx], al
    inc r14
    inc r13d
    cmp r13d, 216
    jb .Lbd_h
    mov rax, r14
    lea rdx, [rip+bt_out]
    sub rax, rdx
    cmp eax, 3800
    jb .Lbd_next
    call bot_flush
    lea r14, [rip+bt_out]
.Lbd_next:
    inc r12d
    cmp r12d, BT_N
    jb .Lbd_sc
    call bot_flush
    lea r14, [rip+bt_out]
    LEAVE

# bot_flush : écrit bt_out (jusqu'à r14) dans 421_bot.bin (ajout) puis remet r14 au début
bot_flush:
    ENTER
    lea rcx, [rip+bt_name]
    mov edx, 0x40000000
    xor r8d, r8d
    xor r9d, r9d
    mov dword ptr [rsp+32], 4               # OPEN_ALWAYS
    mov dword ptr [rsp+40], 0x80
    mov qword ptr [rsp+48], 0
    call CreateFileA
    mov rbx, rax
    cmp rax, -1
    je .Lbf_end
    mov rcx, rbx
    xor edx, edx
    xor r8d, r8d
    mov r9d, 2                              # FILE_END
    call SetFilePointer
    lea rdx, [rip+bt_out]
    mov r8, r14
    sub r8, rdx
    mov rcx, rbx
    lea r9, [rip+g_written]
    mov qword ptr [rsp+32], 0
    call WriteFile
    mov rcx, rbx
    call CloseHandle
    lea r14, [rip+bt_out]
.Lbf_end:
    LEAVE
.endif
