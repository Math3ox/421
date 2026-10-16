# ============================================================
#  421 en 3D isométrique — fenêtre Windows, assembleur x86-64
#  GNU as (syntaxe Intel) + API Windows (user32 / gdi32), sans CRT.
#
#  Build :  build.bat
#  Touches : ESPACE = lancer les dés · F12 = capture (421_shot.bmp) · Échap = quitter
# ============================================================
.intel_syntax noprefix

.equ BUFW, 2200                   # tampon de dessin (x2 pour l'anticrénelage)
.equ BUFH, 1600
.equ WW, 1100                   # zone cliente de la fenêtre
.equ WH, 800

# ---- structure d'un dé (DSTRIDE octets) ----
.equ DSTRIDE, 320
.equ D_VAL,   0                 # dd valeur 1..6
.equ D_HELD,  4                 # dd 1 = gardé
.equ D_AX,    8                 # dq position de repos (a = droite)
.equ D_BY,    16                # dq position de repos (b = vers le joueur)
.equ D_YAW,   24                # dq
.equ D_SA,    32                # dq position de départ du lancer
.equ D_SB,    40
.equ D_AXX,   48                # dq axe de rotation du lancer
.equ D_AXY,   56
.equ D_AXZ,   64
.equ D_ANG0,  72                # dq angle total de rotation
.equ D_AMP,   80                # dq hauteur des rebonds
.equ D_ROLL,  88                # dd 1 = fait partie du lancer en cours
.equ D_WREST, 96                # 9 dq : orientation finale
.equ D_W,     168               # 9 dq : orientation courante
.equ D_P,     240               # 3 dq : position monde du centre
.equ D_DEPTH, 264               # dq profondeur (tri)

.macro RGB name, r, g, b
.equ \name, ((\b) << 16) | ((\g) << 8) | (\r)
.endm

RGB C_BG,      18, 22, 29
RGB C_FLOORSH, 10, 13, 18
RGB C_WOOD,    128, 84, 44
RGB C_WOODSIDE,78, 48, 24
RGB C_WOODLINE,52, 32, 16
RGB C_SHADOW,  6, 52, 34
RGB C_EDGE,    150, 142, 120
RGB C_PIP,     26, 26, 32
RGB C_PIPRED,  196, 30, 30
RGB C_ZONE,    40, 160, 104
RGB C_GOLD,    255, 205, 70
RGB C_POTTOP,  255, 214, 70
RGB C_POTSIDE, 176, 132, 20
RGB C_PLTOP,   96, 200, 255
RGB C_PLSIDE,  30, 104, 160
RGB C_BOTTOP,  255, 110, 130
RGB C_BOTSIDE, 150, 40, 62
RGB C_WHITE,   240, 240, 235
RGB C_TXTGND,  190, 235, 205
RGB C_HELDDISC, 176, 140, 36

.macro ENTER
    push rbp
    mov rbp, rsp
    push rbx
    push rsi
    push rdi
    push r12
    push r13
    push r14
    push r15
    sub rsp, 168
.endm

.macro LEAVE
    add rsp, 168
    pop r15
    pop r14
    pop r13
    pop r12
    pop rdi
    pop rsi
    pop rbx
    pop rbp
    ret
.endm

# ------------------------------------------------------------
.section .rdata,"dr"
.balign 16
k_absmask:  .quad 0x7FFFFFFFFFFFFFFF, 0x7FFFFFFFFFFFFFFF
.balign 8
k_one:      .double 1.0
k_half:     .double 0.5
k_r0:       .double 0.70710678118654752
k_u0:       .double 0.40824829046386302
k_u2:       .double 0.81649658092772604
k_ysq:      .double 0.57735026918962576
k_pi:       .double 3.14159265358979324
k_halfpi:   .double 1.57079632679489662
k_jit:      .double 0.6
k_inv32:    .double 2.3283064365386963e-10
k_h:        .double 0.68        # demi-côté d'un dé
k_felt:     .double 0.10        # hauteur du tapis
k_chipr:    .double 0.5
k_chiph:    .double 0.17
k_chipdx:   .double 1.2
k_shx:      .double 0.625
k_shy:      .double -0.3125
k_lx:       .double -0.512
k_ly:       .double 0.256
k_lz:       .double 0.82
k_la:       .double 0.45
k_lk:       .double 0.55
k_dr:       .double 246.0
k_dg:       .double 240.0
k_db:       .double 224.0
k_pr:       .double 0.20        # rayon d'un point
k_pn:       .double 1.004
k_invdur:   .double 0.00066667  # 1 / 1500 ms
k_two:      .double 2.0
k_five:     .double 5.0
k_six:      .double 6.0
k_amp0:     .double 1.4
k_heldr:    .double 1.4
k_stb:      .double 4.0
k_row:      .double 2.6

k_corner:   .double -1.0,-1.0, 1.0,-1.0, 1.0,1.0, -1.0,1.0
k_pipx:     .double -0.5,0.0,0.5, -0.5,0.0,0.5, -0.5,0.0,0.5
k_pipy:     .double -0.5,-0.5,-0.5, 0.0,0.0,0.0, 0.5,0.5,0.5
k_spot:     .double -2.3, 0.0, 2.3
k_ring:     .double 1.0,0.0, 0.8660254,0.5, 0.5,0.8660254, 0.0,1.0
            .double -0.5,0.8660254, -0.8660254,0.5, -1.0,0.0, -0.8660254,-0.5
            .double -0.5,-0.8660254, 0.0,-1.0, 0.5,-0.8660254, 0.8660254,-0.5

# face v (1..6) : normale n, axes a et b  (a x b = n), 9 doubles par face
facetab:
    .double 0,0,1,   1,0,0,   0,1,0        # 1 : dessus
    .double 1,0,0,   0,1,0,   0,0,1        # 2
    .double 0,1,0,   0,0,1,   1,0,0        # 3
    .double 0,-1,0,  0,0,1,   -1,0,0       # 4
    .double -1,0,0,  0,1,0,   0,0,-1       # 5
    .double 0,0,-1,  1,0,0,   0,-1,0       # 6 : dessous
k_pipmask:  .word 0x010, 0x101, 0x111, 0x145, 0x155, 0x16D
init_vals:  .byte 4, 2, 1, 6, 3, 5, 0, 0

c_class:    .asciz "Dice421Win"
c_title:    .asciz "421 - jeu du bistro en 3D isom\351trique"
c_face:     .asciz "Segoe UI"
c_shot:     .asciz "421_shot.bmp"

s_pot:      .asciz "POT"
s_toi:      .asciz "TOI"
s_bot:      .asciz "BOT"
s_h1:       .asciz "421"
s_msg:      .asciz "ESPACE : lancer les d\351s"

# ------------------------------------------------------------
.data
.balign 16
g_s:        .double 128.0       # échelle monde -> pixels (tampon x2)
g_cylz:     .double 0.10
g_gtz:      .double 0.10
g_cx:       .double 1100.0
g_cy:       .double 900.0
g_xf:       .float 1.0, 0.0, 0.0, 0.57735027, 0.0, 0.0
g_rng:      .quad 0x2545F4914F6CDD1D
g_bmiBig:   .long 40, BUFW, -BUFH
            .short 1, 32
            .long 0, BUFW*BUFH*4, 0, 0, 0, 0
g_bmiSmall: .long 40, WW, -WH
            .short 1, 32
            .long 0, WW*WH*4, 0, 0, 0, 0
g_bmphdr:   .ascii "BM"
            .long 54 + WW*WH*4, 0, 54
            .long 40, WW, -WH
            .short 1, 32
            .long 0, WW*WH*4, 0, 0, 0, 0
g_pot:      .long 11
g_ptok:     .long 3
g_btok:     .long 2
g_msg:      .quad s_msg

.bss
.balign 16
g_hwnd:     .skip 8
g_hinst:    .skip 8
g_hdc:      .skip 8             # DC du grand tampon
g_hdcSmall: .skip 8
g_bigbits:  .skip 8
g_smallbits:.skip 8
g_dcbrush:  .skip 8
g_dcpen:    .skip 8
g_nullpen:  .skip 8
g_nullbrush:.skip 8
g_fontG:    .skip 8
g_fontH:    .skip 8
g_wc:       .skip 80
g_msgbuf:   .skip 48
g_ps:       .skip 72
g_rect:     .skip 16
g_written:  .skip 8
g_dirty:    .skip 4
g_rolling:  .skip 4
g_tstart:   .skip 4
g_ctop:     .skip 4
g_cside:    .skip 4
.balign 8
g_t:        .skip 8
tmp_d:      .skip 8
tmp_d2:     .skip 8
rt_s:       .skip 8
rt_c:       .skip 8
rt_t:       .skip 8
ud_t:       .skip 8
ud_e:       .skip 8
ud_u3:      .skip 8
ud_a:       .skip 8
ud_b:       .skip 8
ud_R:       .skip 72
g_M1:       .skip 72
g_M2:       .skip 72
g_nw:       .skip 24
g_aw:       .skip 24
g_bw:       .skip 24
g_P:        .skip 24
g_tmp3:     .skip 24
g_tmp:      .skip 8
g_pts:      .skip 128
g_order:    .skip 8
cy_a:       .skip 8
cy_b:       .skip 8
cy_z0:      .skip 8
cy_rho:     .skip 8
cy_h:       .skip 8
ch_a0:      .skip 8
ch_b0:      .skip 8
ch_a:       .skip 8
g_dice:     .skip DSTRIDE*6
g_side:     .skip 8
g_fontB:    .skip 8
g_fontM:    .skip 8

# ------------------------------------------------------------
.text
.globl start

# ---------- mathématiques (feuilles, sans pile) ----------

# sincos_d : xmm0 = angle -> xmm0 = sin, xmm1 = cos
sincos_d:
    movsd qword ptr [rip+tmp_d], xmm0
    fld qword ptr [rip+tmp_d]
    fsincos
    fstp qword ptr [rip+tmp_d2]     # cos
    fstp qword ptr [rip+tmp_d]      # sin
    movsd xmm1, qword ptr [rip+tmp_d2]
    movsd xmm0, qword ptr [rip+tmp_d]
    ret

# rng_next : eax = 32 bits aléatoires (xorshift64)
rng_next:
    mov rax, qword ptr [rip+g_rng]
    mov rdx, rax
    shl rdx, 13
    xor rax, rdx
    mov rdx, rax
    shr rdx, 7
    xor rax, rdx
    mov rdx, rax
    shl rdx, 17
    xor rax, rdx
    mov qword ptr [rip+g_rng], rax
    shr rax, 32
    ret

# rng_unit : xmm0 = réel dans [0,1)
rng_unit:
    call rng_next
    cvtsi2sd xmm0, rax
    mulsd xmm0, qword ptr [rip+k_inv32]
    ret

# mv3 : [rdi] = M[rsi] * v[rdx]   (3x3, doubles)
mv3:
    movsd xmm0, qword ptr [rdx]
    movsd xmm1, qword ptr [rdx+8]
    movsd xmm2, qword ptr [rdx+16]
    .irp o, 0, 24, 48
    movsd xmm3, qword ptr [rsi+\o]
    mulsd xmm3, xmm0
    movsd xmm4, qword ptr [rsi+\o+8]
    mulsd xmm4, xmm1
    addsd xmm3, xmm4
    movsd xmm4, qword ptr [rsi+\o+16]
    mulsd xmm4, xmm2
    addsd xmm3, xmm4
    movsd qword ptr [rdi+\o/3], xmm3
    .endr
    ret

# matmul3 : [rdi] = [rsi] * [rdx]  (3x3, doubles ; pas d'alias)
matmul3:
    .irp i, 0, 24, 48
    .irp j, 0, 8, 16
    movsd xmm0, qword ptr [rsi+\i]
    mulsd xmm0, qword ptr [rdx+\j]
    movsd xmm1, qword ptr [rsi+\i+8]
    mulsd xmm1, qword ptr [rdx+24+\j]
    addsd xmm0, xmm1
    movsd xmm1, qword ptr [rsi+\i+16]
    mulsd xmm1, qword ptr [rdx+48+\j]
    addsd xmm0, xmm1
    movsd qword ptr [rdi+\i+\j], xmm0
    .endr
    .endr
    ret

# rodrigues : [rdi] = rotation d'axe unitaire [rsi], angle xmm0
rodrigues:
    call sincos_d
    movsd qword ptr [rip+rt_s], xmm0
    movsd qword ptr [rip+rt_c], xmm1
    movsd xmm2, qword ptr [rip+k_one]
    subsd xmm2, xmm1
    movsd qword ptr [rip+rt_t], xmm2        # t = 1 - cos
    movsd xmm0, qword ptr [rsi]             # ax
    movsd xmm1, qword ptr [rsi+8]           # ay
    movsd xmm2, qword ptr [rsi+16]          # az
    movapd xmm3, xmm0
    mulsd xmm3, xmm0
    mulsd xmm3, qword ptr [rip+rt_t]
    addsd xmm3, qword ptr [rip+rt_c]
    movsd qword ptr [rdi], xmm3             # R00
    movapd xmm3, xmm1
    mulsd xmm3, xmm1
    mulsd xmm3, qword ptr [rip+rt_t]
    addsd xmm3, qword ptr [rip+rt_c]
    movsd qword ptr [rdi+32], xmm3          # R11
    movapd xmm3, xmm2
    mulsd xmm3, xmm2
    mulsd xmm3, qword ptr [rip+rt_t]
    addsd xmm3, qword ptr [rip+rt_c]
    movsd qword ptr [rdi+64], xmm3          # R22
    movapd xmm3, xmm0
    mulsd xmm3, xmm1
    mulsd xmm3, qword ptr [rip+rt_t]        # t ax ay
    movapd xmm4, xmm2
    mulsd xmm4, qword ptr [rip+rt_s]        # s az
    movapd xmm5, xmm3
    subsd xmm5, xmm4
    movsd qword ptr [rdi+8], xmm5           # R01
    addsd xmm3, xmm4
    movsd qword ptr [rdi+24], xmm3          # R10
    movapd xmm3, xmm0
    mulsd xmm3, xmm2
    mulsd xmm3, qword ptr [rip+rt_t]        # t ax az
    movapd xmm4, xmm1
    mulsd xmm4, qword ptr [rip+rt_s]        # s ay
    movapd xmm5, xmm3
    addsd xmm5, xmm4
    movsd qword ptr [rdi+16], xmm5          # R02
    subsd xmm3, xmm4
    movsd qword ptr [rdi+48], xmm3          # R20
    movapd xmm3, xmm1
    mulsd xmm3, xmm2
    mulsd xmm3, qword ptr [rip+rt_t]        # t ay az
    movapd xmm4, xmm0
    mulsd xmm4, qword ptr [rip+rt_s]        # s ax
    movapd xmm5, xmm3
    subsd xmm5, xmm4
    movsd qword ptr [rdi+40], xmm5          # R12
    addsd xmm3, xmm4
    movsd qword ptr [rdi+56], xmm3          # R21
    ret

# proj : projection isométrique. [rsi] = point monde (x,y,z), [rdi] = POINT écran
proj:
    movsd xmm0, qword ptr [rsi]
    movsd xmm1, qword ptr [rsi+8]
    movsd xmm2, qword ptr [rsi+16]
    movapd xmm3, xmm0
    subsd xmm3, xmm1
    mulsd xmm3, qword ptr [rip+k_r0]        # abscisse écran
    addsd xmm0, xmm1
    mulsd xmm0, qword ptr [rip+k_u0]
    mulsd xmm2, qword ptr [rip+k_u2]
    addsd xmm0, xmm2                        # hauteur écran
    movsd xmm1, qword ptr [rip+g_s]
    mulsd xmm3, xmm1
    mulsd xmm0, xmm1
    addsd xmm3, qword ptr [rip+g_cx]
    movsd xmm2, qword ptr [rip+g_cy]
    subsd xmm2, xmm0
    cvtsd2si eax, xmm3
    mov dword ptr [rdi], eax
    cvtsd2si eax, xmm2
    mov dword ptr [rdi+4], eax
    ret

# scr_ground : xmm0 = a, xmm1 = b, xmm2 = z  ->  xmm0 = X écran, xmm1 = Y écran
#              (a = vers la droite, b = vers le joueur, sur le plateau)
scr_ground:
    movsd xmm4, qword ptr [rip+g_s]
    mulsd xmm0, xmm4
    addsd xmm0, qword ptr [rip+g_cx]
    mulsd xmm1, xmm4
    mulsd xmm1, qword ptr [rip+k_ysq]
    addsd xmm1, qword ptr [rip+g_cy]
    mulsd xmm2, xmm4
    mulsd xmm2, qword ptr [rip+k_u2]
    subsd xmm1, xmm2
    ret

strlen_z:
    xor eax, eax
1:  cmp byte ptr [rsi+rax], 0
    je 2f
    inc eax
    jmp 1b
2:  ret

# ---------- petits outils GDI ----------
set_brush:                          # ecx = COLORREF
    sub rsp, 40
    mov edx, ecx
    mov rcx, qword ptr [rip+g_hdc]
    call SetDCBrushColor
    add rsp, 40
    ret

set_pen:
    sub rsp, 40
    mov edx, ecx
    mov rcx, qword ptr [rip+g_hdc]
    call SetDCPenColor
    add rsp, 40
    ret

set_txt:
    sub rsp, 40
    mov edx, ecx
    mov rcx, qword ptr [rip+g_hdc]
    call SetTextColor
    add rsp, 40
    ret

pen_off:
    sub rsp, 40
    mov rcx, qword ptr [rip+g_hdc]
    mov rdx, qword ptr [rip+g_nullpen]
    call SelectObject
    add rsp, 40
    ret

pen_on:
    sub rsp, 40
    mov rcx, qword ptr [rip+g_hdc]
    mov rdx, qword ptr [rip+g_dcpen]
    call SelectObject
    add rsp, 40
    ret

brush_off:
    sub rsp, 40
    mov rcx, qword ptr [rip+g_hdc]
    mov rdx, qword ptr [rip+g_nullbrush]
    call SelectObject
    add rsp, 40
    ret

brush_on:
    sub rsp, 40
    mov rcx, qword ptr [rip+g_hdc]
    mov rdx, qword ptr [rip+g_dcbrush]
    call SelectObject
    add rsp, 40
    ret

sel_font:                           # rcx = HFONT
    sub rsp, 40
    mov rdx, rcx
    mov rcx, qword ptr [rip+g_hdc]
    call SelectObject
    add rsp, 40
    ret

# ground_ellipse : xmm0 = a, xmm1 = b, xmm2 = z, xmm3 = rayon (unités monde)
ground_ellipse:
    ENTER
    call scr_ground                 # xmm0 = SX, xmm1 = SY (xmm3 intact)
    mulsd xmm3, qword ptr [rip+g_s] # rx
    movapd xmm2, xmm3
    mulsd xmm2, qword ptr [rip+k_ysq]   # ry
    movapd xmm4, xmm0
    subsd xmm4, xmm3
    cvtsd2si edx, xmm4              # gauche
    movapd xmm4, xmm1
    subsd xmm4, xmm2
    cvtsd2si r8d, xmm4              # haut
    movapd xmm4, xmm0
    addsd xmm4, xmm3
    cvtsd2si r9d, xmm4              # droite
    addsd xmm1, xmm2
    cvtsd2si eax, xmm1
    mov dword ptr [rsp+32], eax     # bas
    mov rcx, qword ptr [rip+g_hdc]
    call Ellipse
    LEAVE

# draw_cylinder : xmm0 = a, xmm1 = b, xmm2 = z0, xmm3 = rayon, xmm4 = hauteur
#                 couleurs : g_ctop / g_cside
draw_cylinder:
    ENTER
    movsd qword ptr [rip+cy_a], xmm0
    movsd qword ptr [rip+cy_b], xmm1
    movsd qword ptr [rip+cy_z0], xmm2
    movsd qword ptr [rip+cy_rho], xmm3
    movsd qword ptr [rip+cy_h], xmm4
    mov ecx, dword ptr [rip+g_cside]
    call set_brush
    movsd xmm0, qword ptr [rip+cy_a]
    movsd xmm1, qword ptr [rip+cy_b]
    movsd xmm2, qword ptr [rip+cy_z0]
    movsd xmm3, qword ptr [rip+cy_rho]
    call ground_ellipse             # base
    movsd xmm0, qword ptr [rip+cy_a]
    subsd xmm0, qword ptr [rip+cy_rho]
    movsd xmm1, qword ptr [rip+cy_b]
    movsd xmm2, qword ptr [rip+cy_z0]
    addsd xmm2, qword ptr [rip+cy_h]
    call scr_ground                 # coin haut-gauche
    cvtsd2si r12d, xmm0
    cvtsd2si r13d, xmm1
    movsd xmm0, qword ptr [rip+cy_a]
    addsd xmm0, qword ptr [rip+cy_rho]
    movsd xmm1, qword ptr [rip+cy_b]
    movsd xmm2, qword ptr [rip+cy_z0]
    call scr_ground                 # coin bas-droit
    cvtsd2si r9d, xmm0
    inc r9d
    cvtsd2si eax, xmm1
    inc eax
    mov dword ptr [rsp+32], eax
    mov rcx, qword ptr [rip+g_hdc]
    mov edx, r12d
    mov r8d, r13d
    call Rectangle                  # flanc
    mov ecx, dword ptr [rip+g_ctop]
    call set_brush
    mov ecx, dword ptr [rip+g_cside]
    call set_pen
    call pen_on
    movsd xmm0, qword ptr [rip+cy_a]
    movsd xmm1, qword ptr [rip+cy_b]
    movsd xmm2, qword ptr [rip+cy_z0]
    addsd xmm2, qword ptr [rip+cy_h]
    movsd xmm3, qword ptr [rip+cy_rho]
    call ground_ellipse             # dessus
    call pen_off
    LEAVE

# draw_chips : xmm0 = a, xmm1 = b, edi = nombre de jetons (piles de 6)
draw_chips:
    ENTER
    movsd qword ptr [rip+ch_a0], xmm0
    movsd qword ptr [rip+ch_b0], xmm1
    mov esi, edi
    test esi, esi
    jz .Lch_done
    lea eax, [rsi+5]
    xor edx, edx
    mov ecx, 6
    div ecx
    mov r12d, eax                   # nombre de piles
    xor r13d, r13d
.Lch_stack:
    imul eax, r13d, 6
    mov ecx, esi
    sub ecx, eax
    cmp ecx, 6
    jbe 1f
    mov ecx, 6
1:  mov r14d, ecx                   # hauteur de la pile
    cvtsi2sd xmm0, r13d
    cvtsi2sd xmm1, r12d
    subsd xmm1, qword ptr [rip+k_one]
    mulsd xmm1, qword ptr [rip+k_half]
    subsd xmm0, xmm1
    mulsd xmm0, qword ptr [rip+k_chipdx]
    addsd xmm0, qword ptr [rip+ch_a0]
    movsd qword ptr [rip+ch_a], xmm0
    xor r15d, r15d
.Lch_chip:
    movsd xmm0, qword ptr [rip+ch_a]
    movsd xmm1, qword ptr [rip+ch_b0]
    cvtsi2sd xmm2, r15d
    mulsd xmm2, qword ptr [rip+k_chiph]
    addsd xmm2, qword ptr [rip+k_felt]
    movsd xmm3, qword ptr [rip+k_chipr]
    movsd xmm4, qword ptr [rip+k_chiph]
    call draw_cylinder
    inc r15d
    cmp r15d, r14d
    jb .Lch_chip
    inc r13d
    cmp r13d, r12d
    jb .Lch_stack
.Lch_done:
    LEAVE

# draw_ground_text : rsi = texte, xmm0 = a, xmm1 = b (posé sur le tapis, centré)
draw_ground_text:
    ENTER
    mov r12, rsi
    movsd xmm2, qword ptr [rip+g_gtz]
    call scr_ground
    cvtsd2ss xmm0, xmm0
    movss dword ptr [rip+g_xf+16], xmm0
    cvtsd2ss xmm1, xmm1
    movss dword ptr [rip+g_xf+20], xmm1
    mov rsi, r12
    call strlen_z
    mov r13d, eax
    mov rcx, qword ptr [rip+g_hdc]
    mov edx, 6                      # TA_CENTER
    call SetTextAlign
    mov rcx, qword ptr [rip+g_hdc]
    lea rdx, [rip+g_xf]
    call SetWorldTransform
    mov rcx, qword ptr [rip+g_hdc]
    xor edx, edx
    xor r8d, r8d
    mov r9, r12
    mov dword ptr [rsp+32], r13d
    call TextOutA
    mov rcx, qword ptr [rip+g_hdc]
    xor edx, edx
    mov r8d, 1                      # MWT_IDENTITY
    call ModifyWorldTransform
    LEAVE

# draw_flat : ecx = x, edx = y (tampon), r8 = texte, r9d = alignement (0 gauche, 6 centre)
draw_flat:
    ENTER
    mov r12d, ecx
    mov r13d, edx
    mov r14, r8
    mov r15d, r9d
    mov rsi, r14
    call strlen_z
    mov ebx, eax
    mov rcx, qword ptr [rip+g_hdc]
    mov edx, r15d
    call SetTextAlign
    mov rcx, qword ptr [rip+g_hdc]
    mov edx, r12d
    mov r8d, r13d
    mov r9, r14
    mov dword ptr [rsp+32], ebx
    call TextOutA
    LEAVE

# ---------- les dés ----------

# set_rest : rdi = dé, esi = valeur. Calcule l'orientation de repos (valeur au-dessus, lacet aléatoire).
set_rest:
    push rbx
    push r12
    mov rbx, rdi
    mov r12d, esi
    mov dword ptr [rbx+D_VAL], esi
    call rng_next
    shr eax, 30
    cvtsi2sd xmm0, eax
    mulsd xmm0, qword ptr [rip+k_halfpi]
    movsd qword ptr [rip+g_tmp], xmm0
    call rng_unit
    subsd xmm0, qword ptr [rip+k_half]
    mulsd xmm0, qword ptr [rip+k_jit]
    addsd xmm0, qword ptr [rip+g_tmp]
    movsd qword ptr [rbx+D_YAW], xmm0
    call sincos_d                   # xmm0 = sin, xmm1 = cos
    movsd qword ptr [rip+g_M2], xmm1
    movsd qword ptr [rip+g_M2+32], xmm1
    movapd xmm2, xmm0
    movsd qword ptr [rip+g_M2+24], xmm0
    xorpd xmm3, xmm3
    subsd xmm3, xmm2
    movsd qword ptr [rip+g_M2+8], xmm3
    xorpd xmm3, xmm3
    movsd qword ptr [rip+g_M2+16], xmm3
    movsd qword ptr [rip+g_M2+40], xmm3
    movsd qword ptr [rip+g_M2+48], xmm3
    movsd qword ptr [rip+g_M2+56], xmm3
    movsd xmm3, qword ptr [rip+k_one]
    movsd qword ptr [rip+g_M2+64], xmm3
    lea rsi, [rip+facetab]
    imul ecx, r12d, 72
    sub ecx, 72
    add rsi, rcx
    .irp o, 0, 8, 16
    mov rax, qword ptr [rsi+24+\o]
    mov qword ptr [rip+g_M1+\o], rax
    mov rax, qword ptr [rsi+48+\o]
    mov qword ptr [rip+g_M1+24+\o], rax
    mov rax, qword ptr [rsi+\o]
    mov qword ptr [rip+g_M1+48+\o], rax
    .endr
    lea rdi, [rbx+D_WREST]
    lea rsi, [rip+g_M2]
    lea rdx, [rip+g_M1]
    call matmul3
    pop r12
    pop rbx
    ret

# update_die : rdi = dé, xmm0 = t (0..1) ; calcule orientation courante, position, profondeur
update_die:
    push rbx
    mov rbx, rdi
    movsd qword ptr [rip+ud_t], xmm0
    movsd xmm1, qword ptr [rip+k_one]
    subsd xmm1, xmm0
    movapd xmm2, xmm1
    mulsd xmm2, xmm1
    mulsd xmm2, xmm1                # (1-t)^3
    movsd qword ptr [rip+ud_u3], xmm2
    movsd xmm0, qword ptr [rbx+D_ANG0]
    mulsd xmm0, xmm2
    lea rdi, [rip+ud_R]
    lea rsi, [rbx+D_AXX]
    call rodrigues
    lea rdi, [rbx+D_W]
    lea rsi, [rip+ud_R]
    lea rdx, [rbx+D_WREST]
    call matmul3
    movsd xmm0, qword ptr [rip+k_one]
    subsd xmm0, qword ptr [rip+ud_u3]   # e = 1 - (1-t)^3
    movsd qword ptr [rip+ud_e], xmm0
    movsd xmm1, qword ptr [rbx+D_AX]
    subsd xmm1, qword ptr [rbx+D_SA]
    mulsd xmm1, xmm0
    addsd xmm1, qword ptr [rbx+D_SA]
    movsd qword ptr [rip+ud_a], xmm1
    movsd xmm1, qword ptr [rbx+D_BY]
    subsd xmm1, qword ptr [rbx+D_SB]
    mulsd xmm1, xmm0
    addsd xmm1, qword ptr [rbx+D_SB]
    movsd qword ptr [rip+ud_b], xmm1
    # rebonds : amp * (1-t) * |sin(3 pi t)|
    movsd xmm0, qword ptr [rip+ud_t]
    mulsd xmm0, qword ptr [rip+k_pi]
    movapd xmm1, xmm0
    addsd xmm0, xmm1
    addsd xmm0, xmm1                # 3 pi t
    call sincos_d
    andpd xmm0, xmmword ptr [rip+k_absmask]
    movsd xmm1, qword ptr [rip+k_one]
    subsd xmm1, qword ptr [rip+ud_t]
    mulsd xmm0, xmm1
    mulsd xmm0, qword ptr [rbx+D_AMP]
    movsd qword ptr [rip+g_tmp], xmm0   # z supplémentaire
    # hauteur du centre pour que le point le plus bas touche le tapis
    movsd xmm1, qword ptr [rbx+D_W+48]
    andpd xmm1, xmmword ptr [rip+k_absmask]
    movsd xmm2, qword ptr [rbx+D_W+56]
    andpd xmm2, xmmword ptr [rip+k_absmask]
    addsd xmm1, xmm2
    movsd xmm2, qword ptr [rbx+D_W+64]
    andpd xmm2, xmmword ptr [rip+k_absmask]
    addsd xmm1, xmm2
    mulsd xmm1, qword ptr [rip+k_h]
    addsd xmm1, qword ptr [rip+g_tmp]
    addsd xmm1, qword ptr [rip+k_felt]
    cmp dword ptr [rbx+D_HELD], 0
    je 1f
    addsd xmm1, qword ptr [rip+k_half]
1:  movsd qword ptr [rbx+D_P+16], xmm1
    movsd xmm2, qword ptr [rip+ud_a]
    movsd xmm3, qword ptr [rip+ud_b]
    movapd xmm4, xmm2
    subsd xmm4, xmm3
    mulsd xmm4, qword ptr [rip+k_r0]
    movsd qword ptr [rbx+D_P], xmm4     # x = (a - b) / sqrt2
    addsd xmm2, xmm3
    mulsd xmm2, qword ptr [rip+k_r0]
    xorpd xmm5, xmm5
    subsd xmm5, xmm2
    movsd qword ptr [rbx+D_P+8], xmm5   # y = -(a + b) / sqrt2
    addsd xmm4, xmm5
    subsd xmm4, xmm1
    movsd qword ptr [rbx+D_DEPTH], xmm4
    pop rbx
    ret

# init_dice : six dés au repos (toi : 0-2 en bas, bot : 3-5 en haut)
init_dice:
    ENTER
    xor r12d, r12d
.Lid:
    imul eax, r12d, DSTRIDE
    lea rbx, [rip+g_dice]
    add rbx, rax
    lea rax, [rip+init_vals]
    movzx esi, byte ptr [rax+r12]
    mov rdi, rbx
    call set_rest
    mov eax, r12d
    xor edx, edx
    mov ecx, 3
    div ecx
    lea rax, [rip+k_spot]
    movsd xmm0, qword ptr [rax+rdx*8]
    movsd qword ptr [rbx+D_AX], xmm0
    movsd qword ptr [rbx+D_SA], xmm0
    movsd xmm0, qword ptr [rip+k_row]
    cmp r12d, 3
    jb 1f
    xorpd xmm1, xmm1
    subsd xmm1, xmm0
    movapd xmm0, xmm1
1:  movsd qword ptr [rbx+D_BY], xmm0
    movsd qword ptr [rbx+D_SB], xmm0
    xorpd xmm0, xmm0
    movsd qword ptr [rbx+D_ANG0], xmm0
    movsd qword ptr [rbx+D_AMP], xmm0
    movsd xmm0, qword ptr [rip+k_one]
    movsd qword ptr [rbx+D_AXX], xmm0
    xorpd xmm0, xmm0
    movsd qword ptr [rbx+D_AXY], xmm0
    movsd qword ptr [rbx+D_AXZ], xmm0
    mov dword ptr [rbx+D_HELD], 0
    mov dword ptr [rbx+D_ROLL], 0
    mov rdi, rbx
    movsd xmm0, qword ptr [rip+k_one]
    call update_die
    inc r12d
    cmp r12d, 6
    jb .Lid
    LEAVE

# start_throw : ecx = masque des dés à lancer (bits 0-2 : toi, bits 3-5 : bot)
start_throw:
    ENTER
    mov r12d, ecx
    xor r13d, r13d
.Lst_clr:
    imul eax, r13d, DSTRIDE
    lea rbx, [rip+g_dice]
    mov dword ptr [rbx+rax+D_ROLL], 0
    inc r13d
    cmp r13d, 6
    jb .Lst_clr
    xor r13d, r13d
.Lst:
    bt r12d, r13d
    jnc .Lst_next
    imul eax, r13d, DSTRIDE
    lea rbx, [rip+g_dice]
    add rbx, rax
    call rng_next
    mov ecx, 6
    mul ecx
    lea esi, [rdx+1]
    mov rdi, rbx
    call set_rest
    mov dword ptr [rbx+D_HELD], 0
    mov dword ptr [rbx+D_ROLL], 1
    mov eax, r13d
    xor edx, edx
    mov ecx, 3
    div ecx
    mov r14d, edx                   # colonne 0..2
    lea rax, [rip+k_spot]
    movsd xmm0, qword ptr [rax+r14*8]
    movsd qword ptr [rbx+D_AX], xmm0
    movsd xmm1, qword ptr [rip+k_one]
    cmp r13d, 3
    jb 1f
    xorpd xmm2, xmm2
    subsd xmm2, xmm1
    movapd xmm1, xmm2               # côté : +1 toi, -1 bot
1:  movsd qword ptr [rip+g_side], xmm1
    call rng_unit
    subsd xmm0, qword ptr [rip+k_half]
    mulsd xmm0, qword ptr [rip+k_jit]
    movsd xmm1, qword ptr [rip+g_side]
    mulsd xmm1, qword ptr [rip+k_row]
    addsd xmm0, xmm1
    movsd qword ptr [rbx+D_BY], xmm0
    call rng_unit
    subsd xmm0, qword ptr [rip+k_half]
    mulsd xmm0, qword ptr [rip+k_two]
    movsd qword ptr [rbx+D_SA], xmm0
    movsd xmm0, qword ptr [rip+k_stb]
    mulsd xmm0, qword ptr [rip+g_side]
    movsd qword ptr [rbx+D_SB], xmm0
    call rng_unit
    subsd xmm0, qword ptr [rip+k_half]
    movsd qword ptr [rbx+D_AXX], xmm0
    call rng_unit
    subsd xmm0, qword ptr [rip+k_half]
    movsd qword ptr [rbx+D_AXY], xmm0
    call rng_unit
    subsd xmm0, qword ptr [rip+k_half]
    movsd qword ptr [rbx+D_AXZ], xmm0
    movsd xmm0, qword ptr [rbx+D_AXX]
    mulsd xmm0, xmm0
    movsd xmm1, qword ptr [rbx+D_AXY]
    mulsd xmm1, xmm1
    addsd xmm0, xmm1
    movsd xmm1, qword ptr [rbx+D_AXZ]
    mulsd xmm1, xmm1
    addsd xmm0, xmm1
    sqrtsd xmm0, xmm0
    addsd xmm0, qword ptr [rip+k_inv32]
    .irp o, 48, 56, 64
    movsd xmm1, qword ptr [rbx+\o]
    divsd xmm1, xmm0
    movsd qword ptr [rbx+\o], xmm1
    .endr
    call rng_unit
    mulsd xmm0, qword ptr [rip+k_six]
    addsd xmm0, qword ptr [rip+k_five]
    mulsd xmm0, qword ptr [rip+k_pi]
    movsd qword ptr [rbx+D_ANG0], xmm0
    call rng_unit
    addsd xmm0, qword ptr [rip+k_amp0]
    movsd qword ptr [rbx+D_AMP], xmm0
.Lst_next:
    inc r13d
    cmp r13d, 6
    jb .Lst
    call GetTickCount
    mov dword ptr [rip+g_tstart], eax
    mov dword ptr [rip+g_rolling], 1
    mov dword ptr [rip+g_dirty], 1
    LEAVE

# tick : avance l'animation et les actions différées (appelé par le timer)
tick:
    ENTER
    cmp dword ptr [rip+g_rolling], 0
    je .Ltk_wake
    xor r15d, r15d
    call GetTickCount
    sub eax, dword ptr [rip+g_tstart]
    cvtsi2sd xmm0, rax
    mulsd xmm0, qword ptr [rip+k_invdur]
    movsd xmm1, qword ptr [rip+k_one]
    comisd xmm0, xmm1
    jb 1f
    movsd xmm0, xmm1
    mov dword ptr [rip+g_rolling], 0
    mov r15d, 1
1:  movsd qword ptr [rip+g_t], xmm0
    xor r12d, r12d
.Ltk_die:
    imul eax, r12d, DSTRIDE
    lea rdi, [rip+g_dice]
    add rdi, rax
    movsd xmm0, qword ptr [rip+g_t]
    cmp dword ptr [rdi+D_ROLL], 0
    jne 2f
    movsd xmm0, qword ptr [rip+k_one]
2:  call update_die
    inc r12d
    cmp r12d, 6
    jb .Ltk_die
    mov dword ptr [rip+g_dirty], 1
    test r15d, r15d
    jz .Ltk_wake
    call on_roll_done
.Ltk_wake:
    cmp dword ptr [rip+g_wake], 0
    je .Ltk_done
    call GetTickCount
    sub eax, dword ptr [rip+g_wake]
    js .Ltk_done
    mov dword ptr [rip+g_wake], 0
    mov ecx, dword ptr [rip+g_wakeact]
    call do_action
.Ltk_done:
    LEAVE

# calc_face : rbx = dé, r12d = face 0..5  ->  g_nw, g_aw, g_bw (vecteurs de la face dans le monde)
calc_face:
    lea r10, [rip+facetab]
    imul ecx, r12d, 72
    add r10, rcx
    lea rsi, [rbx+D_W]
    lea rdi, [rip+g_nw]
    mov rdx, r10
    call mv3
    lea rdi, [rip+g_aw]
    lea rdx, [r10+24]
    call mv3
    lea rdi, [rip+g_bw]
    lea rdx, [r10+48]
    call mv3
    ret

# calc_pt : xmm0 = kn, xmm1 = ka, xmm2 = kb  ->  g_tmp3 = P + h (kn n + ka a + kb b)
calc_pt:
    .irp o, 0, 8, 16
    movsd xmm3, qword ptr [rip+g_nw+\o]
    mulsd xmm3, xmm0
    movsd xmm4, qword ptr [rip+g_aw+\o]
    mulsd xmm4, xmm1
    addsd xmm3, xmm4
    movsd xmm4, qword ptr [rip+g_bw+\o]
    mulsd xmm4, xmm2
    addsd xmm3, xmm4
    mulsd xmm3, qword ptr [rip+k_h]
    addsd xmm3, qword ptr [rip+g_P+\o]
    movsd qword ptr [rip+g_tmp3+\o], xmm3
    .endr
    ret

# draw_die_shadow : rdi = dé (ombre portée seulement)
draw_die_shadow:
    ENTER
    mov rbx, rdi
    mov rax, qword ptr [rbx+D_P]
    mov qword ptr [rip+g_P], rax
    mov rax, qword ptr [rbx+D_P+8]
    mov qword ptr [rip+g_P+8], rax
    mov rax, qword ptr [rbx+D_P+16]
    mov qword ptr [rip+g_P+16], rax
    # --- ombre portée ---
    mov ecx, C_SHADOW
    call set_brush
    xor r12d, r12d
.Lsh_face:
    call calc_face
    xor r13d, r13d
.Lsh_corner:
    lea rax, [rip+k_corner]
    mov ecx, r13d
    shl ecx, 4
    movsd xmm1, qword ptr [rax+rcx]
    movsd xmm2, qword ptr [rax+rcx+8]
    movsd xmm0, qword ptr [rip+k_one]
    call calc_pt
    movsd xmm0, qword ptr [rip+g_tmp3+16]
    movapd xmm1, xmm0
    mulsd xmm0, qword ptr [rip+k_shx]
    addsd xmm0, qword ptr [rip+g_tmp3]
    movsd qword ptr [rip+g_tmp3], xmm0
    mulsd xmm1, qword ptr [rip+k_shy]
    addsd xmm1, qword ptr [rip+g_tmp3+8]
    movsd qword ptr [rip+g_tmp3+8], xmm1
    xorpd xmm2, xmm2
    movsd qword ptr [rip+g_tmp3+16], xmm2
    lea rdi, [rip+g_pts]
    mov eax, r13d
    lea rdi, [rdi+rax*8]
    lea rsi, [rip+g_tmp3]
    call proj
    inc r13d
    cmp r13d, 4
    jb .Lsh_corner
    mov rcx, qword ptr [rip+g_hdc]
    lea rdx, [rip+g_pts]
    mov r8d, 4
    call Polygon
    inc r12d
    cmp r12d, 6
    jb .Lsh_face
    LEAVE

# draw_die : rdi = dé (corps : faces visibles et points)
draw_die:
    ENTER
    mov rbx, rdi
    mov rax, qword ptr [rbx+D_P]
    mov qword ptr [rip+g_P], rax
    mov rax, qword ptr [rbx+D_P+8]
    mov qword ptr [rip+g_P+8], rax
    mov rax, qword ptr [rbx+D_P+16]
    mov qword ptr [rip+g_P+16], rax
    # --- faces visibles ---
    xor r12d, r12d
.Lface:
    call calc_face
    movsd xmm0, qword ptr [rip+g_nw]
    addsd xmm0, qword ptr [rip+g_nw+8]
    subsd xmm0, qword ptr [rip+g_nw+16]
    xorpd xmm1, xmm1
    comisd xmm0, xmm1
    jae .Lface_next                 # face cachée
    movsd xmm0, qword ptr [rip+g_nw]
    mulsd xmm0, qword ptr [rip+k_lx]
    movsd xmm1, qword ptr [rip+g_nw+8]
    mulsd xmm1, qword ptr [rip+k_ly]
    addsd xmm0, xmm1
    movsd xmm1, qword ptr [rip+g_nw+16]
    mulsd xmm1, qword ptr [rip+k_lz]
    addsd xmm0, xmm1
    xorpd xmm1, xmm1
    maxsd xmm0, xmm1
    mulsd xmm0, qword ptr [rip+k_lk]
    addsd xmm0, qword ptr [rip+k_la]    # éclairement
    movsd xmm1, qword ptr [rip+k_dr]
    mulsd xmm1, xmm0
    cvtsd2si eax, xmm1
    movsd xmm1, qword ptr [rip+k_dg]
    mulsd xmm1, xmm0
    cvtsd2si ecx, xmm1
    movsd xmm1, qword ptr [rip+k_db]
    mulsd xmm1, xmm0
    cvtsd2si edx, xmm1
    shl edx, 16
    shl ecx, 8
    or eax, ecx
    or eax, edx
    mov ecx, eax
    call set_brush
    mov ecx, C_EDGE
    cmp dword ptr [rbx+D_HELD], 0
    je 7f
    mov ecx, C_GOLD
7:  call set_pen
    xor r13d, r13d
.Lf_corner:
    lea rax, [rip+k_corner]
    mov ecx, r13d
    shl ecx, 4
    movsd xmm1, qword ptr [rax+rcx]
    movsd xmm2, qword ptr [rax+rcx+8]
    movsd xmm0, qword ptr [rip+k_one]
    call calc_pt
    lea rdi, [rip+g_pts]
    mov eax, r13d
    lea rdi, [rdi+rax*8]
    lea rsi, [rip+g_tmp3]
    call proj
    inc r13d
    cmp r13d, 4
    jb .Lf_corner
    call pen_on
    mov rcx, qword ptr [rip+g_hdc]
    lea rdx, [rip+g_pts]
    mov r8d, 4
    call Polygon
    call pen_off
    # points
    lea rax, [rip+k_pipmask]
    movzx r13d, word ptr [rax+r12*2]
    mov ecx, C_PIP
    test r12d, r12d
    jnz 1f
    mov ecx, C_PIPRED
1:  call set_brush
    xor r14d, r14d
.Lpip:
    bt r13d, r14d
    jnc .Lpip_next
    xor r15d, r15d
.Lring:
    lea rax, [rip+k_ring]
    mov ecx, r15d
    shl ecx, 4
    movsd xmm1, qword ptr [rax+rcx]
    movsd xmm2, qword ptr [rax+rcx+8]
    mulsd xmm1, qword ptr [rip+k_pr]
    mulsd xmm2, qword ptr [rip+k_pr]
    lea rax, [rip+k_pipx]
    addsd xmm1, qword ptr [rax+r14*8]
    lea rax, [rip+k_pipy]
    addsd xmm2, qword ptr [rax+r14*8]
    movsd xmm0, qword ptr [rip+k_pn]
    call calc_pt
    lea rdi, [rip+g_pts]
    mov eax, r15d
    lea rdi, [rdi+rax*8]
    lea rsi, [rip+g_tmp3]
    call proj
    inc r15d
    cmp r15d, 12
    jb .Lring
    mov rcx, qword ptr [rip+g_hdc]
    lea rdx, [rip+g_pts]
    mov r8d, 12
    call Polygon
.Lpip_next:
    inc r14d
    cmp r14d, 9
    jb .Lpip
.Lface_next:
    inc r12d
    cmp r12d, 6
    jb .Lface
    LEAVE

# draw_dice_all : anneaux des dés gardés, puis les six dés du plus loin au plus proche
draw_dice_all:
    ENTER
    xor r12d, r12d
.Ldd_ring:
    imul eax, r12d, DSTRIDE
    lea rbx, [rip+g_dice]
    add rbx, rax
    cmp dword ptr [rbx+D_HELD], 0
    je .Ldd_rnext
    mov ecx, C_HELDDISC
    call set_brush
    movsd xmm0, qword ptr [rbx+D_AX]
    movsd xmm1, qword ptr [rbx+D_BY]
    movsd xmm2, qword ptr [rip+k_felt]
    movsd xmm3, qword ptr [rip+k_heldr]
    call ground_ellipse
    call brush_off
    mov ecx, C_GOLD
    call set_pen
    call pen_on
    movsd xmm0, qword ptr [rbx+D_AX]
    movsd xmm1, qword ptr [rbx+D_BY]
    movsd xmm2, qword ptr [rip+k_felt]
    movsd xmm3, qword ptr [rip+k_heldr]
    call ground_ellipse
    call pen_off
    call brush_on
.Ldd_rnext:
    inc r12d
    cmp r12d, 6
    jb .Ldd_ring
    xor ecx, ecx
    lea rax, [rip+g_order]
1:  mov byte ptr [rax+rcx], cl
    inc ecx
    cmp ecx, 6
    jb 1b
    mov r13d, 5
.Ldd_pass:
    xor r12d, r12d
.Ldd_j:
    lea r8, [rip+g_order]
    movzx eax, byte ptr [r8+r12]
    movzx ecx, byte ptr [r8+r12+1]
    lea r9, [rip+g_dice]
    imul edx, eax, DSTRIDE
    movsd xmm0, qword ptr [r9+rdx+D_DEPTH]
    imul edx, ecx, DSTRIDE
    movsd xmm1, qword ptr [r9+rdx+D_DEPTH]
    comisd xmm0, xmm1
    jae 2f
    mov byte ptr [r8+r12], cl
    mov byte ptr [r8+r12+1], al
2:  inc r12d
    cmp r12d, 5
    jb .Ldd_j
    dec r13d
    jnz .Ldd_pass
    xor r12d, r12d
.Ldd_sh:
    lea rax, [rip+g_order]
    movzx eax, byte ptr [rax+r12]
    imul eax, eax, DSTRIDE
    lea rdi, [rip+g_dice]
    add rdi, rax
    call draw_die_shadow
    inc r12d
    cmp r12d, 6
    jb .Ldd_sh
    xor r12d, r12d
.Ldd:
    lea rax, [rip+g_order]
    movzx eax, byte ptr [rax+r12]
    imul eax, eax, DSTRIDE
    lea rdi, [rip+g_dice]
    add rdi, rax
    call draw_die
    inc r12d
    cmp r12d, 6
    jb .Ldd
    LEAVE

# ---------- le plateau ----------

draw_table:
    ENTER
    # ombre au sol
    mov ecx, C_FLOORSH
    call set_brush
    xorpd xmm0, xmm0
    xorpd xmm1, xmm1
    mov rax, 0xBFEE666666666666     # -0.95
    movq xmm2, rax
    mov rax, 0x4020666666666666     # 8.2
    movq xmm3, rax
    call ground_ellipse
    # pied + flanc en bois, dessus du rebord
    mov dword ptr [rip+g_ctop], C_WOOD
    mov dword ptr [rip+g_cside], C_WOODSIDE
    xorpd xmm0, xmm0
    xorpd xmm1, xmm1
    mov rax, 0xBFEE666666666666     # z0 = -0.95
    movq xmm2, rax
    mov rax, 0x401C000000000000     # rayon 7.0
    movq xmm3, rax
    mov rax, 0x3FF0CCCCCCCCCCCD     # hauteur 1.05
    movq xmm4, rax
    call draw_cylinder
    # tapis : anneaux concentriques, du bord vers le centre
    xor r12d, r12d
.Lfelt:
    mov eax, r12d
    imul eax, 18
    xor edx, edx
    mov ecx, 15
    div ecx
    add eax, 10                     # rouge
    mov r13d, eax
    mov eax, r12d
    imul eax, 58
    xor edx, edx
    mov ecx, 15
    div ecx
    add eax, 70                     # vert
    mov r14d, eax
    mov eax, r12d
    imul eax, 36
    xor edx, edx
    mov ecx, 15
    div ecx
    add eax, 44                     # bleu
    shl eax, 16
    shl r14d, 8
    or eax, r14d
    or eax, r13d
    mov ecx, eax
    call set_brush
    cvtsi2sd xmm3, r12d
    mov rax, 0x3FB1EB851EB851EC     # 0.07
    movq xmm4, rax
    mulsd xmm3, xmm4                # 0.07 k  (en rayon : retrait)
    mov rax, 0x4019666666666666     # 6.35
    movq xmm4, rax
    mulsd xmm3, xmm4
    subsd xmm4, xmm3                # rayon = 6.35 (1 - 0.07 k)
    movapd xmm3, xmm4
    xorpd xmm0, xmm0
    xorpd xmm1, xmm1
    movsd xmm2, qword ptr [rip+g_cylz]
    call ground_ellipse
    inc r12d
    cmp r12d, 16
    jb .Lfelt
    # liseré du bord du tapis + zones de jeu
    call brush_off
    mov ecx, C_WOODLINE
    call set_pen
    call pen_on
    xorpd xmm0, xmm0
    xorpd xmm1, xmm1
    movsd xmm2, qword ptr [rip+g_cylz]
    mov rax, 0x4019666666666666
    movq xmm3, rax
    call ground_ellipse
    mov ecx, C_ZONE
    call set_pen
    mov rax, 0xC012666666666666     # -4.6
    movq xmm0, rax
    xorpd xmm1, xmm1
    movsd xmm2, qword ptr [rip+g_cylz]
    mov rax, 0x3FF8000000000000     # 1.5
    movq xmm3, rax
    call ground_ellipse             # pot
    xorpd xmm0, xmm0
    mov rax, 0x4013333333333333     # 4.8
    movq xmm1, rax
    movsd xmm2, qword ptr [rip+g_cylz]
    mov rax, 0x3FF8000000000000
    movq xmm3, rax
    call ground_ellipse             # joueur
    xorpd xmm0, xmm0
    movsd xmm1, qword ptr [rip+k_botz]
    movsd xmm2, qword ptr [rip+g_cylz]
    mov rax, 0x3FF8000000000000
    movq xmm3, rax
    call ground_ellipse             # bot
    call pen_off
    call brush_on
    LEAVE

# ---------- image complète ----------

# downsample : tampon x2 -> fenêtre (moyenne 2x2 par pavgb)
downsample:
    mov rsi, qword ptr [rip+g_bigbits]
    mov rdi, qword ptr [rip+g_smallbits]
    mov r8d, WH
.Lds_row:
    lea rdx, [rsi+BUFW*4]
    mov ecx, WW/4
.Lds_blk:
    movdqu xmm0, xmmword ptr [rsi]
    movdqu xmm1, xmmword ptr [rdx]
    pavgb xmm0, xmm1
    movdqu xmm2, xmmword ptr [rsi+16]
    movdqu xmm3, xmmword ptr [rdx+16]
    pavgb xmm2, xmm3
    pshufd xmm4, xmm0, 0x88
    pshufd xmm0, xmm0, 0xDD
    pavgb xmm0, xmm4
    pshufd xmm4, xmm2, 0x88
    pshufd xmm2, xmm2, 0xDD
    pavgb xmm2, xmm4
    punpcklqdq xmm0, xmm2
    movdqu xmmword ptr [rdi], xmm0
    add rsi, 32
    add rdx, 32
    add rdi, 16
    dec ecx
    jnz .Lds_blk
    add rsi, BUFW*4
    dec r8d
    jnz .Lds_row
    ret

# save_bmp : écrit la fenêtre dans 421_shot.bmp
save_bmp:
    ENTER
    lea rcx, [rip+c_shot]
    mov edx, 0x40000000
    xor r8d, r8d
    xor r9d, r9d
    mov dword ptr [rsp+32], 2
    mov dword ptr [rsp+40], 0x80
    mov qword ptr [rsp+48], 0
    call CreateFileA
    mov rbx, rax
    cmp rax, -1
    je .Lsb_end
    mov rcx, rbx
    lea rdx, [rip+g_bmphdr]
    mov r8d, 54
    lea r9, [rip+g_written]
    mov qword ptr [rsp+32], 0
    call WriteFile
    mov rcx, rbx
    mov rdx, qword ptr [rip+g_smallbits]
    mov r8d, WW*WH*4
    lea r9, [rip+g_written]
    mov qword ptr [rsp+32], 0
    call WriteFile
    mov rcx, rbx
    call CloseHandle
.Lsb_end:
    LEAVE

# ---------- initialisation graphique ----------
init_gfx:
    ENTER
    mov rcx, qword ptr [rip+g_hwnd]
    call GetDC
    mov r12, rax
    mov rcx, r12
    call CreateCompatibleDC
    mov qword ptr [rip+g_hdc], rax
    mov rcx, r12
    lea rdx, [rip+g_bmiBig]
    xor r8d, r8d
    lea r9, [rip+g_bigbits]
    mov qword ptr [rsp+32], 0
    mov dword ptr [rsp+40], 0
    call CreateDIBSection
    mov rcx, qword ptr [rip+g_hdc]
    mov rdx, rax
    call SelectObject
    mov rcx, r12
    call CreateCompatibleDC
    mov qword ptr [rip+g_hdcSmall], rax
    mov rcx, r12
    lea rdx, [rip+g_bmiSmall]
    xor r8d, r8d
    lea r9, [rip+g_smallbits]
    mov qword ptr [rsp+32], 0
    mov dword ptr [rsp+40], 0
    call CreateDIBSection
    mov rcx, qword ptr [rip+g_hdcSmall]
    mov rdx, rax
    call SelectObject
    mov rcx, qword ptr [rip+g_hwnd]
    mov rdx, r12
    call ReleaseDC
    mov ecx, 18                     # DC_BRUSH
    call GetStockObject
    mov qword ptr [rip+g_dcbrush], rax
    mov ecx, 19                     # DC_PEN
    call GetStockObject
    mov qword ptr [rip+g_dcpen], rax
    mov ecx, 8                      # NULL_PEN
    call GetStockObject
    mov qword ptr [rip+g_nullpen], rax
    mov ecx, 5                      # NULL_BRUSH
    call GetStockObject
    mov qword ptr [rip+g_nullbrush], rax
    mov rcx, qword ptr [rip+g_hdc]
    mov rdx, qword ptr [rip+g_dcbrush]
    call SelectObject
    mov rcx, qword ptr [rip+g_hdc]
    mov rdx, qword ptr [rip+g_nullpen]
    call SelectObject
    mov rcx, qword ptr [rip+g_hdc]
    mov edx, 2                      # GM_ADVANCED
    call SetGraphicsMode
    mov rcx, qword ptr [rip+g_hdc]
    mov edx, 1                      # TRANSPARENT
    call SetBkMode
    # polices
    mov ecx, -80
    xor edx, edx
    xor r8d, r8d
    xor r9d, r9d
    mov dword ptr [rsp+32], 700
    mov dword ptr [rsp+40], 0
    mov dword ptr [rsp+48], 0
    mov dword ptr [rsp+56], 0
    mov dword ptr [rsp+64], 0
    mov dword ptr [rsp+72], 0
    mov dword ptr [rsp+80], 0
    mov dword ptr [rsp+88], 4       # ANTIALIASED_QUALITY
    mov dword ptr [rsp+96], 0
    lea rax, [rip+c_face]
    mov qword ptr [rsp+104], rax
    call CreateFontA
    mov qword ptr [rip+g_fontG], rax
    mov ecx, -84
    xor edx, edx
    xor r8d, r8d
    xor r9d, r9d
    mov dword ptr [rsp+32], 700
    mov dword ptr [rsp+40], 0
    mov dword ptr [rsp+48], 0
    mov dword ptr [rsp+56], 0
    mov dword ptr [rsp+64], 0
    mov dword ptr [rsp+72], 0
    mov dword ptr [rsp+80], 0
    mov dword ptr [rsp+88], 4
    mov dword ptr [rsp+96], 0
    lea rax, [rip+c_face]
    mov qword ptr [rsp+104], rax
    call CreateFontA
    mov qword ptr [rip+g_fontH], rax
    mov ecx, -60
    xor edx, edx
    xor r8d, r8d
    xor r9d, r9d
    mov dword ptr [rsp+32], 600
    mov dword ptr [rsp+40], 0
    mov dword ptr [rsp+48], 0
    mov dword ptr [rsp+56], 0
    mov dword ptr [rsp+64], 0
    mov dword ptr [rsp+72], 0
    mov dword ptr [rsp+80], 0
    mov dword ptr [rsp+88], 4
    mov dword ptr [rsp+96], 0
    lea rax, [rip+c_face]
    mov qword ptr [rsp+104], rax
    call CreateFontA
    mov qword ptr [rip+g_fontM], rax
    mov ecx, -46
    xor edx, edx
    xor r8d, r8d
    xor r9d, r9d
    mov dword ptr [rsp+32], 700
    mov dword ptr [rsp+40], 0
    mov dword ptr [rsp+48], 0
    mov dword ptr [rsp+56], 0
    mov dword ptr [rsp+64], 0
    mov dword ptr [rsp+72], 0
    mov dword ptr [rsp+80], 0
    mov dword ptr [rsp+88], 4
    mov dword ptr [rsp+96], 0
    lea rax, [rip+c_face]
    mov qword ptr [rsp+104], rax
    call CreateFontA
    mov qword ptr [rip+g_fontB], rax
    rdtsc
    shl rdx, 32
    or rax, rdx
    or rax, 1
    mov qword ptr [rip+g_rng], rax
    call init_dice
    call new_game
    LEAVE

# ---------- fenêtre ----------
WndProc:
    ENTER
    mov rbx, rcx
    mov r12d, edx
    mov r13, r8
    mov r14, r9
    cmp r12d, 0x0F
    je .Lw_paint
    cmp r12d, 0x113
    je .Lw_timer
    cmp r12d, 0x14
    je .Lw_erase
    cmp r12d, 0x100
    je .Lw_key
    cmp r12d, 0x201
    je .Lw_click
    cmp r12d, 1
    je .Lw_create
    cmp r12d, 2
    je .Lw_destroy
.Lw_def:
    mov rcx, rbx
    mov edx, r12d
    mov r8, r13
    mov r9, r14
    call DefWindowProcA
    LEAVE
.Lw_erase:
    mov eax, 1
    LEAVE
.Lw_create:
    mov qword ptr [rip+g_hwnd], rbx
    call init_gfx
    mov rcx, rbx
    mov edx, 1
    mov r8d, 15
    xor r9d, r9d
    call SetTimer
    xor eax, eax
    LEAVE
.Lw_destroy:
    xor ecx, ecx
    call PostQuitMessage
    xor eax, eax
    LEAVE
.Lw_timer:
    call tick
    cmp dword ptr [rip+g_dirty], 0
    je .Lw_zero
    mov rcx, rbx
    xor edx, edx
    xor r8d, r8d
    call InvalidateRect
.Lw_zero:
    xor eax, eax
    LEAVE
.Lw_paint:
    mov rcx, rbx
    lea rdx, [rip+g_ps]
    call BeginPaint
    mov r15, rax
    cmp dword ptr [rip+g_dirty], 0
    je 1f
    call render_frame
1:  mov rcx, r15
    xor edx, edx
    xor r8d, r8d
    mov r9d, WW
    mov dword ptr [rsp+32], WH
    mov rax, qword ptr [rip+g_hdcSmall]
    mov qword ptr [rsp+40], rax
    mov dword ptr [rsp+48], 0
    mov dword ptr [rsp+56], 0
    mov dword ptr [rsp+64], 0x00CC0020
    call BitBlt
    mov rcx, rbx
    lea rdx, [rip+g_ps]
    call EndPaint
    xor eax, eax
    LEAVE
.Lw_key:
    cmp r13d, 0x1B
    je .Lw_destroy
    cmp r13d, 0x7B
    jne 1f
    call save_bmp
    jmp .Lw_zero
1:  cmp r13d, 0x20
    jne 2f
    call player_press_main
    jmp .Lw_zero
2:  cmp r13d, 0x0D
    jne 3f
    call player_press_second
    jmp .Lw_zero
3:  cmp r13d, 0x44
    jne .Lw_zero
    call debug_title
    jmp .Lw_zero
.Lw_click:
    mov ecx, r14d
    and ecx, 0xFFFF
    add ecx, ecx
    mov edx, r14d
    shr edx, 16
    and edx, 0xFFFF
    add edx, edx
    call on_click
    jmp .Lw_zero

# ---------- point d'entrée ----------
start:
    sub rsp, 168
    xor ecx, ecx
    call GetModuleHandleA
    mov qword ptr [rip+g_hinst], rax
    call SetProcessDPIAware
    lea rdi, [rip+g_wc]
    mov dword ptr [rdi], 80
    mov dword ptr [rdi+4], 3                # CS_HREDRAW | CS_VREDRAW
    lea rax, [rip+WndProc]
    mov qword ptr [rdi+8], rax
    mov rax, qword ptr [rip+g_hinst]
    mov qword ptr [rdi+24], rax
    xor ecx, ecx
    mov edx, 32512                          # IDC_ARROW
    call LoadCursorA
    mov qword ptr [rdi+40], rax
    lea rax, [rip+c_class]
    mov qword ptr [rdi+64], rax
    lea rcx, [rip+g_wc]
    call RegisterClassExA
    lea rdi, [rip+g_rect]
    mov dword ptr [rdi], 0
    mov dword ptr [rdi+4], 0
    mov dword ptr [rdi+8], WW
    mov dword ptr [rdi+12], WH
    lea rcx, [rip+g_rect]
    mov edx, 0x00CA0000                     # WS_OVERLAPPED | CAPTION | SYSMENU | MINIMIZEBOX
    xor r8d, r8d
    call AdjustWindowRect
    mov eax, dword ptr [rip+g_rect+8]
    sub eax, dword ptr [rip+g_rect]
    mov r10d, eax                           # largeur totale
    mov eax, dword ptr [rip+g_rect+12]
    sub eax, dword ptr [rip+g_rect+4]
    mov r11d, eax                           # hauteur totale
    xor ecx, ecx
    lea rdx, [rip+c_class]
    lea r8, [rip+c_title]
    mov r9d, 0x10CA0000                     # + WS_VISIBLE
    mov dword ptr [rsp+32], 0x80000000      # CW_USEDEFAULT
    mov dword ptr [rsp+40], 0x80000000
    mov dword ptr [rsp+48], r10d
    mov dword ptr [rsp+56], r11d
    mov qword ptr [rsp+64], 0
    mov qword ptr [rsp+72], 0
    mov rax, qword ptr [rip+g_hinst]
    mov qword ptr [rsp+80], rax
    mov qword ptr [rsp+88], 0
    call CreateWindowExA
.Lloop:
    lea rcx, [rip+g_msgbuf]
    xor edx, edx
    xor r8d, r8d
    xor r9d, r9d
    call GetMessageA
    test eax, eax
    jle .Lquit
    lea rcx, [rip+g_msgbuf]
    call TranslateMessage
    lea rcx, [rip+g_msgbuf]
    call DispatchMessageA
    jmp .Lloop
.Lquit:
    xor ecx, ecx
    call ExitProcess

.include "game.s"
