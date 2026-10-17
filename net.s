# ============================================================
#  net.s — duel en ligne à 2 joueurs, connexion TCP directe par IP (inclus par 421.s)
#
#  Principe : « lockstep ». Les deux PC exécutent exactement la même partie (mode 2 joueurs de game.s)
#  avec le même générateur aléatoire (graine envoyée par l'hôte à la connexion). On n'échange que les
#  actions des joueurs : LANCER/RELANCER, VALIDER, dé coché, SUIVANT, REJOUER (12 octets par action).
#  Les actions de l'autre sont mises en file et appliquées quand ce PC est « posé » (dés immobiles),
#  ce qui absorbe les petits décalages d'animation entre les deux machines.
#  L'hôte est le joueur 1 (siège 0), l'invité le joueur 2 (siège 1). Winsock (ws2_32.dll) est chargé
#  seulement quand on ouvre le menu multijoueur (touche N) : aucun coût sinon.
# ============================================================

.equ NET_PORT, 4210
.equ WM_NET, 0x401
.equ NK_HELLO, 1
.equ NK_MAIN, 2
.equ NK_SECOND, 3
.equ NK_TOGGLE, 4
.equ NK_NEXT, 5
.equ NK_NEW, 6
.equ NQ_N, 16                           # taille de la file d'actions (puissance de 2)

.section .rdata,"dr"
.balign 4
s_ws2:      .asciz "ws2_32.dll"
wn_0:       .asciz "WSAStartup"
wn_1:       .asciz "socket"
wn_2:       .asciz "bind"
wn_3:       .asciz "listen"
wn_4:       .asciz "accept"
wn_5:       .asciz "connect"
wn_6:       .asciz "send"
wn_7:       .asciz "recv"
wn_8:       .asciz "closesocket"
wn_9:       .asciz "WSAAsyncSelect"
wn_10:      .asciz "inet_addr"
wn_11:      .asciz "gethostname"
wn_12:      .asciz "gethostbyname"
wn_13:      .asciz "setsockopt"
.balign 8
ws_names:   .quad wn_0, wn_1, wn_2, wn_3, wn_4, wn_5, wn_6, wn_7, wn_8, wn_9, wn_10, wn_11, wn_12, wn_13
ns_one:     .long 1

n_menu1:    .asciz "Multijoueur : H = h\351berger une partie, R = rejoindre (\311chap = annuler)"
n_menu2:    .asciz "Les deux joueurs doivent avoir la m\352me version du jeu."
n_host1:    .asciz "En attente d'un ami... Ton IP : "
n_host2:    .asciz ""
n_host3:    .asciz "Port 4210 (r\351seau local, VPN ou redirection de port). \311chap = annuler."
n_join1:    .asciz "Adresse IP de l'h\364te (Entr\351e = valider) : "
n_join2:    .asciz "Exemple : 192.168.1.20   (autre port : 192.168.1.20:4210). \311chap = annuler."
n_conn1:    .asciz "Connexion en cours... (\311chap = annuler)"
n_badip:    .asciz "Adresse IP invalide. Exemple : 192.168.1.20"
n_failc:    .asciz "Connexion impossible (h\364te absent ou port ferm\351)."
n_nows:     .asciz "R\351seau indisponible sur ce PC."
n_failh:    .asciz "Impossible d'\351couter sur le port 4210 (d\351j\340 utilis\351 ?)."
n_wait:     .asciz "Connect\351 ! Attente du d\351part de la partie..."
n_lost:     .asciz "Connexion perdue : retour \340 la partie locale."
n_cancel:   .asciz "Multijoueur annul\351."
n_unk:      .asciz "?"
n_dot:      .asciz "."
n_slash:    .asciz " / "
n_us:       .asciz "_"
n_you_t1:   .asciz "\300 toi : lance les d\351s ("
n_adv_t1:   .asciz "L'adversaire joue ("
n_t2:       .asciz " lancer(s) max)..."
n_ch2:      .asciz " : l'adversaire choisit ses d\351s..."
n_winr:     .asciz "Tu gagnes la manche ! L'adversaire encaisse "
n_losr:     .asciz "L'adversaire gagne la manche. Tu encaisses "
n_victory:  .asciz "VICTOIRE ! Tu as battu ton adversaire."
n_defeat:   .asciz "Ton adversaire gagne la partie."
n_online:   .asciz "En ligne"
lb_0:       .asciz "TOI "
lb_1:       .asciz "BOT "
lb_2:       .asciz "J1 "
lb_3:       .asciz "J2 "
lb_5:       .asciz "ADV "
.balign 8
lbl_names:  .quad lb_0, lb_1, lb_2, lb_3, lb_0, lb_5, lb_5, lb_0

.data
.balign 4
g_net:      .long 0                     # 0 inactif, 1 écoute, 2 connexion, 3 connecté
g_menu:     .long 0                     # 0 aucun, 1 choix H/R, 2 saisie de l'IP
g_myseat:   .long 0
g_prevtwop: .long 0
g_gameid:   .long 0
nq_head:    .long 0
nq_tail:    .long 0
.balign 8
g_lsock:    .quad -1
g_sock:     .quad -1

.bss
.balign 8
ws_dll:     .skip 8
wsf:        .skip 112
ws_data:    .skip 512
ns_sa:      .skip 16
ns_out:     .skip 16
ns_rx:      .skip 320
ns_nrx:     .skip 4
ns_iplen:   .skip 4
ns_ip:      .skip 48
ns_tmp:     .skip 48
ns_host:    .skip 264
ns_save1:   .skip 192
ns_save2:   .skip 192
nq:         .skip NQ_N*12

.text

# ---------- Winsock à la demande ----------

# ws_load : eax = 1 si Winsock est prêt
ws_load:
    ENTER
    cmp qword ptr [rip+ws_dll], 0
    jne .Lwl_ok
    lea rcx, [rip+s_ws2]
    call LoadLibraryA
    test rax, rax
    jz .Lwl_fail
    mov r12, rax
    xor r13d, r13d
.Lwl_l:
    mov rcx, r12
    lea rax, [rip+ws_names]
    mov rdx, qword ptr [rax+r13*8]
    call GetProcAddress
    test rax, rax
    jz .Lwl_fail
    lea rcx, [rip+wsf]
    mov qword ptr [rcx+r13*8], rax
    inc r13d
    cmp r13d, 14
    jb .Lwl_l
    mov ecx, 0x0202
    lea rdx, [rip+ws_data]
    call qword ptr [rip+wsf]                # WSAStartup
    test eax, eax
    jnz .Lwl_fail
    mov qword ptr [rip+ws_dll], r12
.Lwl_ok:
    mov eax, 1
    jmp .Lwl_end
.Lwl_fail:
    xor eax, eax
.Lwl_end:
    LEAVE

# net_make_addr : rdi = sockaddr (16 octets), eax = adresse IPv4 (ordre réseau), ecx = port
net_make_addr:
    mov word ptr [rdi], 2                   # AF_INET
    mov edx, ecx
    rol dx, 8                               # htons
    mov word ptr [rdi+2], dx
    mov dword ptr [rdi+4], eax
    mov qword ptr [rdi+8], 0
    ret

# net_say1 / net_say2 : rsi = texte -> remplace la ligne 1 / 2 de l'interface
net_say1:
    lea rdi, [rip+g_line1]
    call msg_start                          # msg_start / msg_str ne touchent pas à rsi / la pile
    call msg_str
    mov dword ptr [rip+g_full], 1
    mov dword ptr [rip+g_dirty], 1
    ret

net_say2:
    lea rdi, [rip+g_line2]
    call msg_start
    call msg_str
    mov dword ptr [rip+g_full], 1
    mov dword ptr [rip+g_dirty], 1
    ret

# msg_lbl : ecx = 0/1 -> ajoute l'étiquette du plateau (TOI / BOT / J1 / J2 / ADV)
msg_lbl:
    mov eax, dword ptr [rip+g_twop]
    cmp eax, 2
    jne 1f
    mov eax, dword ptr [rip+g_myseat]
    add eax, 2
1:  lea eax, [rcx+rax*2]
    lea rdx, [rip+lbl_names]
    mov rsi, qword ptr [rdx+rax*8]
    jmp msg_str

# ---------- menu ----------

# net_open : touche N. Ouvre le menu (ou coupe la connexion en cours)
net_open:
    ENTER
    cmp dword ptr [rip+g_net], 0
    je .Lno_menu
    lea rsi, [rip+n_cancel]                 # déjà en cours : on déconnecte
    call net_close
    jmp .Lno_end
.Lno_menu:
    cmp dword ptr [rip+g_menu], 0
    jne .Lno_end
    lea rsi, [rip+g_line1]                  # sauvegarde des messages pour pouvoir annuler
    lea rdi, [rip+ns_save1]
    mov ecx, 192/8
    cld
    rep movsq
    lea rsi, [rip+g_line2]
    lea rdi, [rip+ns_save2]
    mov ecx, 192/8
    rep movsq
    mov dword ptr [rip+g_menu], 1
    lea rsi, [rip+n_menu1]
    call net_say1
    lea rsi, [rip+n_menu2]
    call net_say2
.Lno_end:
    LEAVE

# net_restore : annule le menu et remet les messages d'avant
net_restore:
    lea rsi, [rip+ns_save1]
    lea rdi, [rip+g_line1]
    mov ecx, 192/8
    cld
    rep movsq
    lea rsi, [rip+ns_save2]
    lea rdi, [rip+g_line2]
    mov ecx, 192/8
    rep movsq
    mov dword ptr [rip+g_menu], 0
    mov dword ptr [rip+g_full], 1
    mov dword ptr [rip+g_dirty], 1
    ret

# net_menu_key : ecx = touche virtuelle, appelée quand g_menu != 0
net_menu_key:
    ENTER
    cmp ecx, 0x7B                           # F12 : la capture reste possible dans le menu
    jne 1f
    call save_bmp
    jmp .Lnm_end
1:  cmp dword ptr [rip+g_menu], 1
    jne .Lnm_end                            # en saisie : les caractères arrivent par WM_CHAR
    cmp ecx, 0x48                           # H
    je .Lnm_host
    cmp ecx, 0x52                           # R
    je .Lnm_join
    cmp ecx, 0x10                           # Maj / Ctrl : on ignore
    je .Lnm_end
    cmp ecx, 0x11
    je .Lnm_end
    call net_restore                        # toute autre touche : annuler
    jmp .Lnm_end
.Lnm_host:
    mov dword ptr [rip+g_menu], 0
    call net_host
    jmp .Lnm_end
.Lnm_join:
    mov dword ptr [rip+g_menu], 2
    call net_prompt
.Lnm_end:
    LEAVE

# net_prompt : affiche la saisie de l'IP
net_prompt:
    ENTER
    lea rdi, [rip+g_line1]
    call msg_start
    lea rsi, [rip+n_join1]
    call msg_str
    lea rsi, [rip+ns_ip]
    call msg_str
    lea rsi, [rip+n_us]
    call msg_str
    lea rsi, [rip+n_join2]
    call net_say2
    mov dword ptr [rip+g_full], 1
    mov dword ptr [rip+g_dirty], 1
    LEAVE

# net_char : ecx = caractère (WM_CHAR). Saisie de l'adresse IP
net_char:
    ENTER
    cmp dword ptr [rip+g_menu], 2
    jne .Lnch_end
    cmp ecx, 27                             # Échap
    jne 1f
    call net_restore
    jmp .Lnch_end
1:  cmp ecx, 13                             # Entrée
    jne 2f
    call net_join
    jmp .Lnch_end
2:  cmp ecx, 8                              # Retour arrière
    jne 3f
    mov eax, dword ptr [rip+ns_iplen]
    test eax, eax
    jz .Lnch_end
    dec eax
    mov dword ptr [rip+ns_iplen], eax
    lea rdx, [rip+ns_ip]
    mov byte ptr [rdx+rax], 0
    call net_prompt
    jmp .Lnch_end
3:  cmp ecx, 48                             # chiffres, '.' et ':' seulement
    jb 4f
    cmp ecx, 58
    jbe 5f
    jmp .Lnch_end
4:  cmp ecx, 46
    je 5f
    jmp .Lnch_end
5:  mov eax, dword ptr [rip+ns_iplen]
    cmp eax, 21
    jae .Lnch_end
    lea rdx, [rip+ns_ip]
    mov byte ptr [rdx+rax], cl
    inc eax
    mov byte ptr [rdx+rax], 0
    mov dword ptr [rip+ns_iplen], eax
    call net_prompt
.Lnch_end:
    LEAVE

# ---------- hôte ----------

# net_host : écoute sur le port 4210 et affiche l'IP locale
net_host:
    ENTER
    call ws_load
    test eax, eax
    jnz 1f
    lea rsi, [rip+n_nows]
    call net_say1
    jmp .Lnh_end
1:  mov ecx, 2                              # AF_INET
    mov edx, 1                              # SOCK_STREAM
    mov r8d, 6                              # IPPROTO_TCP
    call qword ptr [rip+wsf+8]
    mov qword ptr [rip+g_lsock], rax
    cmp rax, -1
    je .Lnh_fail
    mov rcx, rax                            # SO_REUSEADDR
    mov edx, 0xFFFF
    mov r8d, 4
    lea r9, [rip+ns_one]
    mov dword ptr [rsp+32], 4
    call qword ptr [rip+wsf+104]
    lea rdi, [rip+ns_sa]
    xor eax, eax
    mov ecx, NET_PORT
    call net_make_addr
    mov rcx, qword ptr [rip+g_lsock]
    lea rdx, [rip+ns_sa]
    mov r8d, 16
    call qword ptr [rip+wsf+16]             # bind
    test eax, eax
    jnz .Lnh_fail
    mov rcx, qword ptr [rip+g_lsock]
    mov edx, 1
    call qword ptr [rip+wsf+24]             # listen
    mov rcx, qword ptr [rip+g_lsock]
    mov rdx, qword ptr [rip+g_hwnd]
    mov r8d, WM_NET
    mov r9d, 8                              # FD_ACCEPT
    call qword ptr [rip+wsf+72]             # WSAAsyncSelect
    mov dword ptr [rip+g_net], 1
    lea rdi, [rip+g_line1]                  # message : IP locale
    call msg_start
    lea rsi, [rip+n_host1]
    call msg_str
    lea rcx, [rip+ns_host]
    mov edx, 256
    call qword ptr [rip+wsf+88]             # gethostname
    lea rcx, [rip+ns_host]
    call qword ptr [rip+wsf+96]             # gethostbyname
    test rax, rax
    jz .Lnh_unk
    mov r15, qword ptr [rax+24]             # h_addr_list : jusqu'à 3 adresses
    test r15, r15
    jz .Lnh_unk
    xor r14d, r14d
.Lnh_e:
    mov r13, qword ptr [r15+r14*8]
    test r13, r13
    jnz 4f
    test r14d, r14d
    jz .Lnh_unk
    jmp .Lnh_tail
4:  test r14d, r14d
    jz 3f
    lea rsi, [rip+n_slash]
    call msg_str
3:  xor r12d, r12d
.Lnh_b:
    movzx eax, byte ptr [r13+r12]
    call msg_num
    inc r12d
    cmp r12d, 4
    jae .Lnh_nxt
    lea rsi, [rip+n_dot]
    call msg_str
    jmp .Lnh_b
.Lnh_nxt:
    inc r14d
    cmp r14d, 3
    jb .Lnh_e
    jmp .Lnh_tail
.Lnh_unk:
    lea rsi, [rip+n_unk]
    call msg_str
.Lnh_tail:
    lea rsi, [rip+n_host2]
    call msg_str
    lea rsi, [rip+n_host3]
    call net_say2
    mov dword ptr [rip+g_full], 1
    mov dword ptr [rip+g_dirty], 1
    jmp .Lnh_end
.Lnh_fail:
    mov rcx, qword ptr [rip+g_lsock]
    cmp rcx, -1
    je 2f
    call qword ptr [rip+wsf+64]             # closesocket
2:  mov qword ptr [rip+g_lsock], -1
    lea rsi, [rip+n_failh]
    call net_say1
.Lnh_end:
    LEAVE

# ---------- invité ----------

# net_join : se connecte à l'adresse saisie (ns_ip)
net_join:
    ENTER
    mov dword ptr [rip+g_menu], 0
    lea rsi, [rip+ns_ip]
    lea rdi, [rip+ns_tmp]
    xor r13d, r13d                          # port saisi (0 = défaut)
.Lnj_cp:
    mov al, byte ptr [rsi]
    test al, al
    jz .Lnj_cpend
    cmp al, 58                              # ':'
    je .Lnj_port
    mov byte ptr [rdi], al
    inc rsi
    inc rdi
    jmp .Lnj_cp
.Lnj_port:
    inc rsi
.Lnj_pd:
    movzx eax, byte ptr [rsi]
    test eax, eax
    jz .Lnj_cpend
    sub eax, 48
    cmp eax, 9
    ja .Lnj_cpend
    imul r13d, r13d, 10
    add r13d, eax
    cmp r13d, 65535
    ja .Lnj_bad
    inc rsi
    jmp .Lnj_pd
.Lnj_cpend:
    mov byte ptr [rdi], 0
    test r13d, r13d
    jnz 1f
    mov r13d, NET_PORT
1:  call ws_load
    test eax, eax
    jnz 2f
    lea rsi, [rip+n_nows]
    call net_say1
    jmp .Lnj_end
2:  lea rcx, [rip+ns_tmp]
    call qword ptr [rip+wsf+80]             # inet_addr
    cmp eax, -1
    je .Lnj_bad
    test eax, eax
    jz .Lnj_bad
    mov r14d, eax
    mov ecx, 2
    mov edx, 1
    mov r8d, 6
    call qword ptr [rip+wsf+8]              # socket
    mov qword ptr [rip+g_sock], rax
    cmp rax, -1
    je .Lnj_failc
    mov rcx, rax
    mov rdx, qword ptr [rip+g_hwnd]
    mov r8d, WM_NET
    mov r9d, 0x31                           # FD_READ | FD_CONNECT | FD_CLOSE
    call qword ptr [rip+wsf+72]             # WSAAsyncSelect
    lea rdi, [rip+ns_sa]
    mov eax, r14d
    mov ecx, r13d
    call net_make_addr
    mov rcx, qword ptr [rip+g_sock]
    lea rdx, [rip+ns_sa]
    mov r8d, 16
    call qword ptr [rip+wsf+40]             # connect (résultat par FD_CONNECT)
    mov dword ptr [rip+g_net], 2
    mov dword ptr [rip+ns_nrx], 0
    lea rsi, [rip+n_conn1]
    call net_say1
    lea rsi, [rip+n_cancel]
    call net_say2_empty
    call opt_save                           # mémorise l'adresse
    jmp .Lnj_end
.Lnj_bad:
    mov dword ptr [rip+g_menu], 2          # IP invalide : on revient à la saisie
    call net_prompt
    lea rsi, [rip+n_badip]
    call net_say2
    jmp .Lnj_end
.Lnj_failc:
    lea rsi, [rip+n_failc]
    call net_say1
.Lnj_end:
    LEAVE

net_say2_empty:
    lea rdi, [rip+g_line2]
    jmp msg_start

# ---------- événements réseau (WM_NET) ----------

# net_event : rcx = socket, edx = lParam (événement dans les 16 bits bas, erreur dans les 16 hauts)
net_event:
    ENTER
    mov eax, edx
    movzx r13d, ax                          # événement
    shr eax, 16
    mov r14d, eax                           # erreur
    test r13d, 8                            # FD_ACCEPT
    jnz .Lne_accept
    test r13d, 0x10                         # FD_CONNECT
    jnz .Lne_conn
    test r13d, 1                            # FD_READ
    jnz .Lne_read
    test r13d, 0x20                         # FD_CLOSE
    jnz .Lne_close
    jmp .Lne_end
.Lne_accept:
    cmp dword ptr [rip+g_net], 1
    jne .Lne_end
    mov rcx, qword ptr [rip+g_lsock]
    xor edx, edx
    xor r8d, r8d
    call qword ptr [rip+wsf+32]             # accept
    cmp rax, -1
    je .Lne_end
    mov qword ptr [rip+g_sock], rax
    mov rcx, qword ptr [rip+g_lsock]        # on n'écoute plus
    call qword ptr [rip+wsf+64]
    mov qword ptr [rip+g_lsock], -1
    mov rcx, qword ptr [rip+g_sock]
    mov rdx, qword ptr [rip+g_hwnd]
    mov r8d, WM_NET
    mov r9d, 0x21                           # FD_READ | FD_CLOSE
    call qword ptr [rip+wsf+72]
    mov dword ptr [rip+g_net], 3
    mov dword ptr [rip+g_myseat], 0
    mov dword ptr [rip+ns_nrx], 0
    mov rax, qword ptr [rip+g_rng]          # HELLO : graine et pot de l'hôte
    mov byte ptr [rip+ns_out], NK_HELLO
    mov ecx, dword ptr [rip+g_potinit]
    mov byte ptr [rip+ns_out+1], cl
    mov word ptr [rip+ns_out+2], 1
    mov dword ptr [rip+ns_out+4], eax
    shr rax, 32
    mov dword ptr [rip+ns_out+8], eax
    call net_send_frame
    mov rax, qword ptr [rip+g_rng]
    mov ecx, dword ptr [rip+g_potinit]
    call net_start_game
    jmp .Lne_end
.Lne_conn:
    test r14d, r14d
    jz 1f
    lea rsi, [rip+n_failc]
    call net_close
    jmp .Lne_end
1:  mov dword ptr [rip+g_net], 3
    mov dword ptr [rip+g_myseat], 1
    lea rsi, [rip+n_wait]
    call net_say1
    jmp .Lne_end
.Lne_read:
    call net_recv
    jmp .Lne_end
.Lne_close:
    lea rsi, [rip+n_lost]
    call net_close
.Lne_end:
    LEAVE

# net_send_frame : envoie les 12 octets de ns_out
net_send_frame:
    sub rsp, 40
    mov rcx, qword ptr [rip+g_sock]
    lea rdx, [rip+ns_out]
    mov r8d, 12
    xor r9d, r9d
    call qword ptr [rip+wsf+48]             # send
    add rsp, 40
    ret

# net_send_act : ecx = type, edx = b (16 bits), r8d = c (32 bits)
net_send_act:
    sub rsp, 40
    cmp dword ptr [rip+g_net], 3
    jne 1f
    mov byte ptr [rip+ns_out], cl
    mov byte ptr [rip+ns_out+1], 0
    mov word ptr [rip+ns_out+2], dx
    mov dword ptr [rip+ns_out+4], r8d
    mov dword ptr [rip+ns_out+8], 0
    mov rcx, qword ptr [rip+g_sock]
    lea rdx, [rip+ns_out]
    mov r8d, 12
    xor r9d, r9d
    call qword ptr [rip+wsf+48]
1:  add rsp, 40
    ret

# net_recv : lit ce qui est arrivé et traite les trames de 12 octets
net_recv:
    ENTER
.Lnr_l:
    mov eax, dword ptr [rip+ns_nrx]
    mov r8d, 256
    sub r8d, eax
    jle .Lnr_done
    mov rcx, qword ptr [rip+g_sock]
    lea rdx, [rip+ns_rx]
    add rdx, rax
    xor r9d, r9d
    call qword ptr [rip+wsf+56]             # recv
    test eax, eax
    jle .Lnr_done
    add dword ptr [rip+ns_nrx], eax
.Lnr_f:
    cmp dword ptr [rip+ns_nrx], 12
    jb .Lnr_l
    lea rsi, [rip+ns_rx]
    call net_frame
    sub dword ptr [rip+ns_nrx], 12
    mov ecx, dword ptr [rip+ns_nrx]
    lea rdi, [rip+ns_rx]
    lea rsi, [rip+ns_rx+12]
    cld
    rep movsb
    jmp .Lnr_f
.Lnr_done:
    LEAVE

# net_frame : rsi = trame reçue
net_frame:
    movzx eax, byte ptr [rsi]
    cmp eax, NK_HELLO
    je .Lnf_hello
    cmp eax, NK_MAIN
    jb .Lnf_ret
    cmp eax, NK_NEW
    ja .Lnf_ret
    mov ecx, dword ptr [rip+nq_tail]        # action : mise en file
    lea edx, [rcx+1]
    and edx, NQ_N-1
    cmp edx, dword ptr [rip+nq_head]
    je .Lnf_ret
    imul r8d, ecx, 12
    lea r9, [rip+nq]
    mov rax, qword ptr [rsi]
    mov qword ptr [r9+r8], rax
    mov eax, dword ptr [rsi+8]
    mov dword ptr [r9+r8+8], eax
    mov dword ptr [rip+nq_tail], edx
.Lnf_ret:
    ret
.Lnf_hello:
    cmp dword ptr [rip+g_myseat], 1         # seul l'invité reçoit un HELLO
    jne .Lnf_ret
    cmp dword ptr [rip+g_net], 3
    jne .Lnf_ret
    movzx ecx, byte ptr [rsi+1]             # pot de l'hôte
    mov eax, dword ptr [rsi+4]
    mov edx, dword ptr [rsi+8]
    shl rdx, 32
    or rax, rdx                             # graine
    jmp net_start_game

# net_start_game : rax = graine, ecx = pot. Lance la partie en ligne (identique des deux côtés)
net_start_game:
    ENTER
    mov qword ptr [rip+g_rng], rax
    cmp dword ptr [rip+g_myseat], 1
    jne 1f
    mov dword ptr [rip+g_potinit], ecx      # l'invité adopte le pot de l'hôte
1:  cmp dword ptr [rip+g_twop], 2
    je 2f
    mov eax, dword ptr [rip+g_twop]
    mov dword ptr [rip+g_prevtwop], eax
2:  mov dword ptr [rip+g_twop], 2
    mov dword ptr [rip+g_menu], 0
    mov dword ptr [rip+nq_head], 0
    mov dword ptr [rip+nq_tail], 0
    mov dword ptr [rip+g_gameid], 0
    call init_dice
    call new_game
    LEAVE

# net_close : rsi = message. Ferme la connexion et revient à la partie locale
net_close:
    ENTER
    mov r12, rsi
    cmp qword ptr [rip+g_sock], -1
    je 1f
    mov rcx, qword ptr [rip+g_sock]
    call qword ptr [rip+wsf+64]
    mov qword ptr [rip+g_sock], -1
1:  cmp qword ptr [rip+g_lsock], -1
    je 2f
    mov rcx, qword ptr [rip+g_lsock]
    call qword ptr [rip+wsf+64]
    mov qword ptr [rip+g_lsock], -1
2:  mov dword ptr [rip+g_net], 0
    mov dword ptr [rip+nq_head], 0
    mov dword ptr [rip+nq_tail], 0
    mov dword ptr [rip+ns_nrx], 0
    cmp dword ptr [rip+g_twop], 2
    jne 3f
    mov dword ptr [rip+g_menu], 0
    mov eax, dword ptr [rip+g_prevtwop]
    mov dword ptr [rip+g_twop], eax
    call new_game                           # partie en ligne finie : nouvelle partie locale
    jmp 4f
3:  call net_restore                        # simple annulation : on remet les messages d'avant
4:  mov rsi, r12
    call net_say2
    LEAVE

# net_cancel : Échap pendant l'attente ou la connexion
net_cancel:
    ENTER
    lea rsi, [rip+n_cancel]
    call net_close
    LEAVE

# ---------- application des actions de l'adversaire ----------

# net_pump : appelée par tick. Applique, dans l'ordre, les actions reçues quand ce PC est posé
net_pump:
    ENTER
.Lnp_again:
    cmp dword ptr [rip+g_net], 3
    jne .Lnp_end
    mov ecx, dword ptr [rip+nq_head]
    cmp ecx, dword ptr [rip+nq_tail]
    je .Lnp_end
    cmp dword ptr [rip+g_rolling], 0
    jne .Lnp_end
    cmp dword ptr [rip+g_wake], 0
    jne .Lnp_end
    imul eax, ecx, 12
    lea rdx, [rip+nq]
    add rdx, rax
    movzx r12d, byte ptr [rdx]
    movzx r13d, word ptr [rdx+2]
    mov r14d, dword ptr [rdx+4]
    inc ecx
    and ecx, NQ_N-1
    mov dword ptr [rip+nq_head], ecx
    cmp r12d, NK_NEXT
    je .Lnp_next
    cmp r12d, NK_NEW
    je .Lnp_new
    mov eax, dword ptr [rip+g_cur]          # actions du joueur courant : seulement si ce n'est pas nous
    cmp eax, dword ptr [rip+g_myseat]
    je .Lnp_again
    cmp r12d, NK_MAIN
    je .Lnp_main
    cmp r12d, NK_SECOND
    je .Lnp_second
    cmp r12d, NK_TOGGLE
    je .Lnp_toggle
    jmp .Lnp_again
.Lnp_main:
    call player_press_main
    jmp .Lnp_again
.Lnp_second:
    call player_press_second
    jmp .Lnp_again
.Lnp_toggle:
    cmp dword ptr [rip+g_phase], PH_CHOOSE
    jne .Lnp_again
    cmp r13d, 2
    ja .Lnp_again
    mov eax, dword ptr [rip+g_cur]
    lea eax, [rax+rax*2]
    add eax, r13d
    imul eax, eax, DSTRIDE
    lea rdi, [rip+g_dice]
    add rdi, rax
    xor dword ptr [rdi+D_HELD], 1
    movsd xmm0, qword ptr [rip+k_one]
    call update_die
    mov dword ptr [rip+g_full], 1
    mov dword ptr [rip+g_dirty], 1
    jmp .Lnp_again
.Lnp_next:
    cmp dword ptr [rip+g_phase], PH_RESULT
    jne .Lnp_again
    cmp r14d, dword ptr [rip+g_round]
    jne .Lnp_again
    call begin_round
    jmp .Lnp_again
.Lnp_new:
    cmp dword ptr [rip+g_phase], PH_OVER
    jne .Lnp_again
    cmp r14d, dword ptr [rip+g_gameid]
    jne .Lnp_again
    call new_game
    jmp .Lnp_again
.Lnp_end:
    LEAVE

# ---------- actions locales : envoi + application ----------

# net_can_act : eax = 1 si le joueur local peut agir (toujours vrai hors ligne)
net_can_act:
    mov eax, 1
    cmp dword ptr [rip+g_twop], 2
    jne 1f
    cmp dword ptr [rip+g_phase], PH_RESULT
    jae 1f
    xor eax, eax
    mov edx, dword ptr [rip+g_cur]
    cmp edx, dword ptr [rip+g_myseat]
    sete al
1:  ret

# ui_main : bouton du haut (LANCER / RELANCER / SUIVANT / REJOUER) pressé par le joueur local
ui_main:
    ENTER
    cmp dword ptr [rip+g_twop], 2
    jne .Lum_do
    mov eax, dword ptr [rip+g_phase]
    cmp eax, PH_PREROLL
    je .Lum_turn
    cmp eax, PH_CHOOSE
    je .Lum_turn
    cmp eax, PH_RESULT
    je .Lum_next
    cmp eax, PH_OVER
    je .Lum_new
    jmp .Lum_end
.Lum_turn:
    mov eax, dword ptr [rip+g_cur]
    cmp eax, dword ptr [rip+g_myseat]
    jne .Lum_end
    mov ecx, NK_MAIN
    xor edx, edx
    xor r8d, r8d
    call net_send_act
    jmp .Lum_do
.Lum_next:
    mov ecx, NK_NEXT
    xor edx, edx
    mov r8d, dword ptr [rip+g_round]
    call net_send_act
    jmp .Lum_do
.Lum_new:
    mov ecx, NK_NEW
    xor edx, edx
    mov r8d, dword ptr [rip+g_gameid]
    call net_send_act
.Lum_do:
    call player_press_main
.Lum_end:
    LEAVE

# ui_second : bouton VALIDER pressé par le joueur local
ui_second:
    ENTER
    cmp dword ptr [rip+g_twop], 2
    jne .Lus_do
    cmp dword ptr [rip+g_phase], PH_CHOOSE
    jne .Lus_end
    mov eax, dword ptr [rip+g_cur]
    cmp eax, dword ptr [rip+g_myseat]
    jne .Lus_end
    mov ecx, NK_SECOND
    xor edx, edx
    xor r8d, r8d
    call net_send_act
.Lus_do:
    call player_press_second
.Lus_end:
    LEAVE

# ui_toggle : ecx = dé (0..2 du joueur) que le joueur local vient de cocher
ui_toggle:
    cmp dword ptr [rip+g_twop], 2
    jne 1f
    mov edx, ecx
    mov ecx, NK_TOGGLE
    xor r8d, r8d
    jmp net_send_act
1:  ret

# ---------- messages en ligne ----------

# net_turn_msg : début du tour de g_cur (g_lim lancers)
net_turn_msg:
    ENTER
    lea rdi, [rip+g_line1]
    call msg_start
    mov eax, dword ptr [rip+g_cur]
    cmp eax, dword ptr [rip+g_myseat]
    jne 1f
    lea rsi, [rip+n_you_t1]
    jmp 2f
1:  lea rsi, [rip+n_adv_t1]
2:  call msg_str
    mov eax, dword ptr [rip+g_lim]
    call msg_num
    lea rsi, [rip+n_t2]
    call msg_str
    LEAVE
