# ============================================================
#  render.s — couche de rendu (inclus par 421.s)
#
#  - décor (table) rendu une fois en 2x puis mis en cache en 1x (bg_clean)
#  - étiquettes + texte d'interface sur un second tampon (bg1)
#  - à chaque image : seule la zone modifiée est restaurée puis redessinée
#  - 4 modes de qualité :
#       0  Haute   : GDI dans un tampon 2x, réduit par moyenne 2x2 (SSE)
#       1  GDI+    : GDI+ avec anticrénelage, en 1x
#       2  Rapide  : rastériseur maison (couverture exacte), en 1x
#       3  Eco     : GDI en 1x sans anticrénelage, 30 images/s
#  - qualité adaptative : on descend de mode si les images coûtent trop cher
# ============================================================


.section .rdata,"dr"
.balign 16
k_absmask_ps: .long 0x7FFFFFFF, 0x7FFFFFFF, 0x7FFFFFFF, 0x7FFFFFFF
.balign 8
k_tgt_s:    .double 128.0, 64.0, 64.0
k_tgt_cx:   .double 1100.0, 550.0, 550.0
k_tgt_cy:   .double 900.0, 450.0, 450.0
k_f1:       .float 1.0
k_fm1:      .float -1.0
k_fhalf:    .float 0.5
k_f15:      .float 1.5
k_f256_255: .float 1.00392157
k_fdil:     .float 0.85
k_feps:     .float 0.0001
k_fcx:      .double 550.0
k_fcy:      .double 450.0
k_fsc:      .double 64.0
k_bbr1:     .double 82.0
k_bbr2:     .double 132.0
k_xl:       .double 0.25

t_mode0:    .asciz "421 - Haute qualit\351 (GDI x2, zones modifi\351es)"
t_mode1:    .asciz "421 - GDI+ liss\351 (1x)"
t_mode2:    .asciz "421 - Rapide (rast\351riseur maison, 1x)"
t_mode3:    .asciz "421 - \311co (GDI 1x, 30 images/s)"
.balign 8
t_modes:    .quad t_mode0, t_mode1, t_mode2, t_mode3
be_of_mode: .long 0, 1, 2, 0
int_of_mode:.long 15, 15, 15, 33

# sommets des 8 coins d'un cube (kn, ka, kb)
k_cube8:    .double -1,-1,-1,  1,-1,-1,  -1,1,-1,  1,1,-1,  -1,-1,1,  1,-1,1,  -1,1,1,  1,1,1

# cercle à 32 sommets (cos, sin)
k_circ:
    .double 1.000000000000, 0.000000000000
    .double 0.980785280403, 0.195090322016
    .double 0.923879532511, 0.382683432365
    .double 0.831469612303, 0.555570233020
    .double 0.707106781187, 0.707106781187
    .double 0.555570233020, 0.831469612303
    .double 0.382683432365, 0.923879532511
    .double 0.195090322016, 0.980785280403
    .double 0.000000000000, 1.000000000000
    .double -0.195090322016, 0.980785280403
    .double -0.382683432365, 0.923879532511
    .double -0.555570233020, 0.831469612303
    .double -0.707106781187, 0.707106781187
    .double -0.831469612303, 0.555570233020
    .double -0.923879532511, 0.382683432365
    .double -0.980785280403, 0.195090322016
    .double -1.000000000000, 0.000000000000
    .double -0.980785280403, -0.195090322016
    .double -0.923879532511, -0.382683432365
    .double -0.831469612303, -0.555570233020
    .double -0.707106781187, -0.707106781187
    .double -0.555570233020, -0.831469612303
    .double -0.382683432365, -0.923879532511
    .double -0.195090322016, -0.980785280403
    .double 0.000000000000, -1.000000000000
    .double 0.195090322016, -0.980785280403
    .double 0.382683432365, -0.923879532511
    .double 0.555570233020, -0.831469612303
    .double 0.707106781187, -0.707106781187
    .double 0.831469612303, -0.555570233020
    .double 0.923879532511, -0.382683432365
    .double 0.980785280403, -0.195090322016


s_gdiplus:  .asciz "gdiplus.dll"
gpn_0:     .asciz "GdiplusStartup"
gpn_1:     .asciz "GdipCreateFromHDC"
gpn_2:     .asciz "GdipSetSmoothingMode"
gpn_3:     .asciz "GdipSetPixelOffsetMode"
gpn_4:     .asciz "GdipCreateSolidFill"
gpn_5:     .asciz "GdipSetSolidFillColor"
gpn_6:     .asciz "GdipFillPolygon"
gpn_7:     .asciz "GdipFlush"
gpn_8:     .asciz "GdipSetClipRectI"
.balign 8
gp_names:   .quad gpn_0, gpn_1, gpn_2, gpn_3, gpn_4, gpn_5, gpn_6, gpn_7, gpn_8

.data
.balign 8
g_R:        .long WW, WH, 0, 0              # zone sale accumulée (l, t, r, b) : vide
g_cR:       .long 0, 0, WW, WH              # zone composée à cette image
g_mode:     .long 0
g_be:       .long 0                         # moteur de primitives : 0 GDI, 1 GDI+, 2 rastériseur
g_auto:     .long 1
g_fs:       .long 0                         # jeu de polices : 0 = 2x, 1 = 1x
g_full:     .long 1
g_tmr:      .long 0
g_interval: .long 15
g_cl:       .long 0
g_ct:       .long 0
g_cr:       .long WW
g_cb:       .long WH
pp_edge:    .long -1
pp_alpha:   .long 255

.bss
.balign 8
g_hdcBig:   .skip 8
g_hbmBig:   .skip 8
g_hbmBg:    .skip 8
g_hdcBg1:   .skip 8
g_bg1bits:  .skip 8
g_bgbits:   .skip 8
g_dcs:      .skip 24
g_fonts:    .skip 64
g_hrgn:     .skip 8
g_qpf:      .skip 8
g_tbg:      .skip 8
g_tfr:      .skip 8
g_q0:       .skip 8
g_q1:       .skip 8
g_sumdt:    .skip 8
g_budget:   .skip 8
g_budget_eco: .skip 8
g_gfxfail:  .skip 4
g_ox:       .skip 4
g_oy:       .skip 4
g_erase:    .skip 4
g_fsmode:   .skip 4
g_wrect:    .skip 16
g_Roff:     .skip 16
g_toterm:   .skip 4
g_cnt:      .skip 4
g_frames:   .skip 4
pp_n:       .skip 4
pp_fill:    .skip 4
pe_cx:      .skip 8
pe_cy:      .skip 8
pe_rx:      .skip 8
pe_ry:      .skip 8
pg_rho:     .skip 8
cy_xl:      .skip 8
cy_yt:      .skip 8
cy_xr:      .skip 8
cy_yb:      .skip 8
bb_sx:      .skip 8
bb_sy:      .skip 8
bb_l:       .skip 4
bb_t:       .skip 4
bb_r:       .skip 4
bb_b:       .skip 4
ra_x0:      .skip 4
ra_y0:      .skip 4
ra_w:       .skip 4
ra_h:       .skip 4
ra_stride:  .skip 4
ra_sbytes:  .skip 4
ra_col:     .skip 4
ra_alpha:   .skip 4
ra_r:       .skip 4
ra_g:       .skip 4
ra_b:       .skip 4
ra_pix:     .skip 4
ra_xs:      .skip 4
ra_xe:      .skip 4
ra_x0f:     .skip 4
ra_y0f:     .skip 4
gp_dll:     .skip 8
gpf:        .skip 72
g_gptoken:  .skip 8
g_gpg:      .skip 8
g_gpbrush:  .skip 8
g_gpin:     .skip 24
g_hull:     .skip 16
.balign 16
g_ptsf2:    .skip 512
g_acc:      .skip (RMAXW+3)*RMAXH*4

.text

# ---------- cibles de dessin ----------

# set_target : ecx = 0 (tampon 2x), 1 (fenêtre 1x), 2 (décor+texte 1x)
set_target:
    lea rax, [rip+k_tgt_s]
    movsd xmm0, qword ptr [rax+rcx*8]
    movsd qword ptr [rip+g_s], xmm0
    lea rax, [rip+k_tgt_cx]
    movsd xmm0, qword ptr [rax+rcx*8]
    movsd qword ptr [rip+g_cx], xmm0
    lea rax, [rip+k_tgt_cy]
    movsd xmm0, qword ptr [rax+rcx*8]
    movsd qword ptr [rip+g_cy], xmm0
    lea rax, [rip+g_dcs]
    mov rax, qword ptr [rax+rcx*8]
    mov qword ptr [rip+g_hdc], rax
    xor eax, eax
    test ecx, ecx
    setnz al
    mov dword ptr [rip+g_fs], eax
    ret

# sel_fontk : ecx = 0 étiquettes, 1 titre, 2 messages, 3 boutons (jeu de polices du tampon courant)
sel_fontk:
    sub rsp, 40
    mov eax, dword ptr [rip+g_fs]
    lea eax, [rcx+rax*4]
    lea rdx, [rip+g_fonts]
    mov rdx, qword ptr [rdx+rax*8]
    mov rcx, qword ptr [rip+g_hdc]
    call SelectObject
    add rsp, 40
    ret

# mkfont : ecx = hauteur, edx = graisse -> rax
mkfont:
    ENTER
    mov r12d, edx
    xor edx, edx
    xor r8d, r8d
    xor r9d, r9d
    mov dword ptr [rsp+32], r12d
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
    LEAVE

# init_dc : rcx = DC. Pinceau/stylo par défaut, mode avancé, fond transparent
init_dc:
    ENTER
    mov r12, rcx
    mov rdx, qword ptr [rip+g_dcbrush]
    call SelectObject
    mov rcx, r12
    mov rdx, qword ptr [rip+g_nullpen]
    call SelectObject
    mov rcx, r12
    mov edx, 2                      # GM_ADVANCED
    call SetGraphicsMode
    mov rcx, r12
    mov edx, 1                      # TRANSPARENT
    call SetBkMode
    LEAVE

# alloc_big / free_big : tampon 2x (14 Mo), seulement pour le mode Haute qualité
alloc_big:
    ENTER
    cmp qword ptr [rip+g_bigbits], 0
    jne .Lab_end
    mov rcx, qword ptr [rip+g_hwnd]
    call GetDC
    mov r12, rax
    mov rcx, r12
    call CreateCompatibleDC
    mov qword ptr [rip+g_hdcBig], rax
    mov qword ptr [rip+g_dcs], rax
    mov rcx, r12
    lea rdx, [rip+g_bmiBig]
    xor r8d, r8d
    lea r9, [rip+g_bigbits]
    mov qword ptr [rsp+32], 0
    mov dword ptr [rsp+40], 0
    call CreateDIBSection
    mov qword ptr [rip+g_hbmBig], rax
    mov rcx, qword ptr [rip+g_hdcBig]
    mov rdx, rax
    call SelectObject
    mov rcx, qword ptr [rip+g_hdcBig]
    call init_dc
    mov rcx, qword ptr [rip+g_hwnd]
    mov rdx, r12
    call ReleaseDC
.Lab_end:
    LEAVE

free_big:
    ENTER
    cmp qword ptr [rip+g_bigbits], 0
    je .Lfb_end
    mov rcx, qword ptr [rip+g_hdcBig]
    call DeleteDC
    mov rcx, qword ptr [rip+g_hbmBig]
    call DeleteObject
    mov qword ptr [rip+g_hdcBig], 0
    mov qword ptr [rip+g_hbmBig], 0
    mov qword ptr [rip+g_bigbits], 0
    mov qword ptr [rip+g_dcs], 0
.Lfb_end:
    LEAVE

# ---------- primitives : polygone, ellipse (GDI / GDI+ / rastériseur) ----------

# prim_poly : points dans g_pts (entiers) et g_pts+PTSF_OFF (flottants), pp_n sommets,
#             pp_fill (couleur), pp_edge (contour ou -1), pp_alpha
prim_poly:
    ENTER
    cmp dword ptr [rip+g_be], 0
    jne .Lpp_aa
    mov ecx, dword ptr [rip+pp_fill]
    call set_brush
    mov ecx, dword ptr [rip+pp_edge]
    cmp ecx, -1
    je 1f
    call set_pen
    call pen_on
1:  mov rcx, qword ptr [rip+g_hdc]
    lea rdx, [rip+g_pts]
    mov r8d, dword ptr [rip+pp_n]
    call Polygon
    cmp dword ptr [rip+pp_edge], -1
    je 2f
    call pen_off
2:  LEAVE
.Lpp_aa:
    call prim_poly_aa
    LEAVE

# prim_poly_aa : contour (par dilatation) puis remplissage, avec GDI+ ou le rastériseur
prim_poly_aa:
    ENTER
    cmp dword ptr [rip+pp_edge], -1
    je .Lpa_fill
    call dilate
    lea rsi, [rip+g_ptsf2]
    mov ecx, dword ptr [rip+pp_n]
    mov edx, dword ptr [rip+pp_edge]
    mov r8d, 255
    call aa_fill
.Lpa_fill:
    lea rsi, [rip+g_pts+PTSF_OFF]
    mov ecx, dword ptr [rip+pp_n]
    mov edx, dword ptr [rip+pp_fill]
    mov r8d, dword ptr [rip+pp_alpha]
    call aa_fill
    LEAVE

# aa_fill : rsi = points flottants, ecx = n, edx = COLORREF, r8d = alpha
aa_fill:
    cmp dword ptr [rip+g_be], 1
    je gp_fill
    jmp rast_poly

# dilate : g_ptsf -> g_ptsf2, chaque sommet repoussé de ~0.85 px depuis le centre (contour)
dilate:
    mov ecx, dword ptr [rip+pp_n]
    lea rsi, [rip+g_pts+PTSF_OFF]
    lea rdi, [rip+g_ptsf2]
    xorps xmm0, xmm0
    xorps xmm1, xmm1
    xor edx, edx
1:  addss xmm0, dword ptr [rsi+rdx*8]
    addss xmm1, dword ptr [rsi+rdx*8+4]
    inc edx
    cmp edx, ecx
    jb 1b
    cvtsi2ss xmm2, ecx
    divss xmm0, xmm2
    divss xmm1, xmm2
    xor edx, edx
2:  movss xmm2, dword ptr [rsi+rdx*8]
    subss xmm2, xmm0
    movss xmm3, dword ptr [rsi+rdx*8+4]
    subss xmm3, xmm1
    movaps xmm4, xmm2
    mulss xmm4, xmm4
    movaps xmm5, xmm3
    mulss xmm5, xmm5
    addss xmm4, xmm5
    sqrtss xmm4, xmm4
    addss xmm4, dword ptr [rip+k_feps]
    movss xmm5, dword ptr [rip+k_fdil]
    divss xmm5, xmm4
    addss xmm5, dword ptr [rip+k_f1]
    mulss xmm2, xmm5
    mulss xmm3, xmm5
    addss xmm2, xmm0
    addss xmm3, xmm1
    movss dword ptr [rdi+rdx*8], xmm2
    movss dword ptr [rdi+rdx*8+4], xmm3
    inc edx
    cmp edx, ecx
    jb 2b
    ret

# prim_ellipse : xmm0 = cx, xmm1 = cy, xmm2 = rx, xmm3 = ry (pixels du tampon courant)
#                pp_fill / pp_edge / pp_alpha
prim_ellipse:
    ENTER
    movsd qword ptr [rip+pe_cx], xmm0
    movsd qword ptr [rip+pe_cy], xmm1
    movsd qword ptr [rip+pe_rx], xmm2
    movsd qword ptr [rip+pe_ry], xmm3
    cmp dword ptr [rip+g_be], 0
    jne .Lpe_aa
    mov ecx, dword ptr [rip+pp_fill]
    call set_brush
    mov ecx, dword ptr [rip+pp_edge]
    cmp ecx, -1
    je 1f
    call set_pen
    call pen_on
1:  movsd xmm0, qword ptr [rip+pe_cx]
    movsd xmm1, qword ptr [rip+pe_cy]
    movsd xmm2, qword ptr [rip+pe_rx]
    movsd xmm3, qword ptr [rip+pe_ry]
    movapd xmm4, xmm0
    subsd xmm4, xmm2
    cvtsd2si edx, xmm4
    movapd xmm4, xmm1
    subsd xmm4, xmm3
    cvtsd2si r8d, xmm4
    movapd xmm4, xmm0
    addsd xmm4, xmm2
    cvtsd2si r9d, xmm4
    addsd xmm1, xmm3
    cvtsd2si eax, xmm1
    mov dword ptr [rsp+32], eax
    mov rcx, qword ptr [rip+g_hdc]
    call Ellipse
    cmp dword ptr [rip+pp_edge], -1
    je 2f
    call pen_off
2:  LEAVE
.Lpe_aa:
    xor ecx, ecx
    lea r8, [rip+g_pts+PTSF_OFF]
    lea rax, [rip+k_circ]
.Lpe_v:
    mov edx, ecx
    shl edx, 4
    movsd xmm0, qword ptr [rax+rdx]
    mulsd xmm0, qword ptr [rip+pe_rx]
    addsd xmm0, qword ptr [rip+pe_cx]
    cvtsd2ss xmm0, xmm0
    movss dword ptr [r8+rcx*8], xmm0
    movsd xmm1, qword ptr [rax+rdx+8]
    mulsd xmm1, qword ptr [rip+pe_ry]
    addsd xmm1, qword ptr [rip+pe_cy]
    cvtsd2ss xmm1, xmm1
    movss dword ptr [r8+rcx*8+4], xmm1
    inc ecx
    cmp ecx, 32
    jb .Lpe_v
    mov dword ptr [rip+pp_n], 32
    call prim_poly_aa
    LEAVE

# prim_ground_ellipse : xmm0 = a, xmm1 = b, xmm2 = z, xmm3 = rayon (unités monde)
prim_ground_ellipse:
    ENTER
    movsd qword ptr [rip+pg_rho], xmm3
    call scr_ground
    movsd xmm2, qword ptr [rip+pg_rho]
    mulsd xmm2, qword ptr [rip+g_s]
    movapd xmm3, xmm2
    mulsd xmm3, qword ptr [rip+k_ysq]
    call prim_ellipse
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
    mov eax, dword ptr [rip+g_cside]
    mov dword ptr [rip+pp_fill], eax
    mov dword ptr [rip+pp_edge], -1
    mov dword ptr [rip+pp_alpha], 255
    movsd xmm0, qword ptr [rip+cy_a]
    movsd xmm1, qword ptr [rip+cy_b]
    movsd xmm2, qword ptr [rip+cy_z0]
    movsd xmm3, qword ptr [rip+cy_rho]
    call prim_ground_ellipse        # base
    movsd xmm0, qword ptr [rip+cy_a]
    subsd xmm0, qword ptr [rip+cy_rho]
    movsd xmm1, qword ptr [rip+cy_b]
    movsd xmm2, qword ptr [rip+cy_z0]
    addsd xmm2, qword ptr [rip+cy_h]
    call scr_ground
    movsd qword ptr [rip+cy_xl], xmm0
    movsd qword ptr [rip+cy_yt], xmm1
    movsd xmm0, qword ptr [rip+cy_a]
    addsd xmm0, qword ptr [rip+cy_rho]
    movsd xmm1, qword ptr [rip+cy_b]
    movsd xmm2, qword ptr [rip+cy_z0]
    call scr_ground
    movsd qword ptr [rip+cy_xr], xmm0
    movsd qword ptr [rip+cy_yb], xmm1
    # flanc : quadrilatère (entiers pour GDI, flottants pour les autres)
    lea rdi, [rip+g_pts]
    cvtsd2si eax, qword ptr [rip+cy_xl]
    cvtsd2si ecx, qword ptr [rip+cy_yt]
    cvtsd2si edx, qword ptr [rip+cy_xr]
    inc edx
    cvtsd2si r8d, qword ptr [rip+cy_yb]
    inc r8d
    mov dword ptr [rdi], eax
    mov dword ptr [rdi+4], ecx
    mov dword ptr [rdi+8], edx
    mov dword ptr [rdi+12], ecx
    mov dword ptr [rdi+16], edx
    mov dword ptr [rdi+20], r8d
    mov dword ptr [rdi+24], eax
    mov dword ptr [rdi+28], r8d
    movsd xmm0, qword ptr [rip+cy_xl]
    subsd xmm0, qword ptr [rip+k_xl]
    cvtsd2ss xmm0, xmm0
    movsd xmm1, qword ptr [rip+cy_xr]
    addsd xmm1, qword ptr [rip+k_xl]
    cvtsd2ss xmm1, xmm1
    movsd xmm2, qword ptr [rip+cy_yt]
    cvtsd2ss xmm2, xmm2
    movsd xmm3, qword ptr [rip+cy_yb]
    cvtsd2ss xmm3, xmm3
    movss dword ptr [rdi+PTSF_OFF], xmm0
    movss dword ptr [rdi+PTSF_OFF+4], xmm2
    movss dword ptr [rdi+PTSF_OFF+8], xmm1
    movss dword ptr [rdi+PTSF_OFF+12], xmm2
    movss dword ptr [rdi+PTSF_OFF+16], xmm1
    movss dword ptr [rdi+PTSF_OFF+20], xmm3
    movss dword ptr [rdi+PTSF_OFF+24], xmm0
    movss dword ptr [rdi+PTSF_OFF+28], xmm3
    mov dword ptr [rip+pp_n], 4
    call prim_poly
    # dessus
    mov eax, dword ptr [rip+g_ctop]
    mov dword ptr [rip+pp_fill], eax
    mov eax, dword ptr [rip+g_cside]
    cmp dword ptr [rip+g_be], 0
    je 1f
    mov eax, -1
1:  mov dword ptr [rip+pp_edge], eax
    movsd xmm0, qword ptr [rip+cy_a]
    movsd xmm1, qword ptr [rip+cy_b]
    movsd xmm2, qword ptr [rip+cy_z0]
    addsd xmm2, qword ptr [rip+cy_h]
    movsd xmm3, qword ptr [rip+cy_rho]
    call prim_ground_ellipse
    mov dword ptr [rip+pp_edge], -1
    LEAVE

# ---------- GDI+ ----------

# gp_load : charge gdiplus.dll à la demande et résout les 9 fonctions utilisées (gp_dll = 0 si échec)
gp_load:
    ENTER
    cmp qword ptr [rip+gp_dll], 0
    jne .Lgl_end
    lea rcx, [rip+s_gdiplus]
    call LoadLibraryA
    test rax, rax
    jz .Lgl_end
    mov r12, rax
    xor r13d, r13d
.Lgl_l:
    mov rcx, r12
    lea rax, [rip+gp_names]
    mov rdx, qword ptr [rax+r13*8]
    call GetProcAddress
    test rax, rax
    jz .Lgl_fail
    lea rcx, [rip+gpf]
    mov qword ptr [rcx+r13*8], rax
    inc r13d
    cmp r13d, 9
    jb .Lgl_l
    mov qword ptr [rip+gp_dll], r12
    jmp .Lgl_end
.Lgl_fail:
    mov qword ptr [rip+gp_dll], 0
.Lgl_end:
    LEAVE

# gp_ensure : démarre GDI+ et crée le contexte graphique sur la fenêtre 1x (une seule fois)
gp_ensure:
    ENTER
    cmp qword ptr [rip+g_gpg], 0
    jne .Lge_end
    call gp_load
    cmp qword ptr [rip+gp_dll], 0
    je .Lge_end
    lea rdi, [rip+g_gpin]
    mov dword ptr [rdi], 1
    mov qword ptr [rdi+8], 0
    mov dword ptr [rdi+16], 0
    mov dword ptr [rdi+20], 0
    lea rcx, [rip+g_gptoken]
    lea rdx, [rip+g_gpin]
    xor r8d, r8d
    call qword ptr [rip+gpf+0]
    test eax, eax
    jnz .Lge_end
    mov rcx, qword ptr [rip+g_hdcSmall]
    lea rdx, [rip+g_gpg]
    call qword ptr [rip+gpf+8]
    test eax, eax
    jz 1f
    mov qword ptr [rip+g_gpg], 0
    jmp .Lge_end
1:  mov rcx, qword ptr [rip+g_gpg]
    mov edx, 4                      # SmoothingModeAntiAlias
    call qword ptr [rip+gpf+16]
    mov rcx, qword ptr [rip+g_gpg]
    mov edx, 4                      # PixelOffsetModeHalf
    call qword ptr [rip+gpf+24]
    mov ecx, 0xFFFFFFFF
    lea rdx, [rip+g_gpbrush]
    call qword ptr [rip+gpf+32]
.Lge_end:
    LEAVE

# gp_fill : rsi = points flottants, ecx = n, edx = COLORREF, r8d = alpha
gp_fill:
    ENTER
    mov r12, rsi
    mov r13d, ecx
    movzx eax, dl                   # R
    shl eax, 16
    movzx ecx, dh                   # G
    shl ecx, 8
    or eax, ecx
    shr edx, 16
    movzx ecx, dl                   # B
    or eax, ecx
    shl r8d, 24
    or eax, r8d
    mov edx, eax
    mov rcx, qword ptr [rip+g_gpbrush]
    call qword ptr [rip+gpf+40]
    mov rcx, qword ptr [rip+g_gpg]
    mov rdx, qword ptr [rip+g_gpbrush]
    mov r8, r12
    mov r9d, r13d
    mov dword ptr [rsp+32], 0       # FillModeAlternate
    call qword ptr [rip+gpf+48]
    LEAVE

# sync_prims : fait aboutir les dessins en attente (GDI+ / GDI) avant/après un mélange avec du texte
sync_prims:
    ENTER
    cmp dword ptr [rip+g_be], 0
    je .Lsp_end
    cmp dword ptr [rip+g_be], 1
    jne 1f
    mov rcx, qword ptr [rip+g_gpg]
    mov edx, 1                      # FlushIntentionSync
    call qword ptr [rip+gpf+56]
1:  call GdiFlush
.Lsp_end:
    LEAVE

# ---------- rastériseur anticrénelé (couverture exacte, accumulation d'aires signées) ----------

.macro FLOORSS x
    cvttss2si eax, \x
    cvtsi2ss xmm5, eax
    comiss xmm5, \x
    jbe 1f
    dec eax
1:
.endm

.macro CEILSS x
    cvttss2si eax, \x
    cvtsi2ss xmm5, eax
    comiss xmm5, \x
    jae 1f
    inc eax
1:
.endm

.macro ACC mem, src
    movss xmm12, dword ptr \mem
    addss xmm12, \src
    movss dword ptr \mem, xmm12
.endm

# rast_edge : accumule l'arête (xmm0,xmm1)-(xmm2,xmm3) (coordonnées relatives à la boîte) dans g_acc
rast_edge:
    comiss xmm1, xmm3
    je .Lre_ret
    movss xmm4, dword ptr [rip+k_f1]        # sens
    jb .Lre_ordered
    movaps xmm5, xmm0
    movaps xmm0, xmm2
    movaps xmm2, xmm5
    movaps xmm5, xmm1
    movaps xmm1, xmm3
    movaps xmm3, xmm5
    movss xmm4, dword ptr [rip+k_fm1]
.Lre_ordered:
    movaps xmm5, xmm2
    subss xmm5, xmm0
    movaps xmm6, xmm3
    subss xmm6, xmm1
    divss xmm5, xmm6                        # dx/dy
    cvttss2si r8d, xmm1                     # première ligne
    cvttss2si r9d, xmm3
    cvtsi2ss xmm6, r9d
    comiss xmm6, xmm3
    jae 1f
    inc r9d                                 # dernière ligne + 1
1:
.Lre_row:
    cmp r8d, r9d
    jge .Lre_ret
    cvtsi2ss xmm6, r8d
    movaps xmm7, xmm6
    addss xmm7, dword ptr [rip+k_f1]
    minss xmm7, xmm3
    maxss xmm6, xmm1
    subss xmm7, xmm6                        # dy
    movaps xmm6, xmm5
    mulss xmm6, xmm7
    addss xmm6, xmm0                        # xn
    mulss xmm7, xmm4                        # d = dy * sens
    movaps xmm8, xmm0
    minss xmm8, xmm6                        # xa
    movaps xmm9, xmm0
    maxss xmm9, xmm6                        # xb
    cvttss2si eax, xmm8                     # x0i
    cvttss2si ecx, xmm9
    cvtsi2ss xmm2, ecx
    comiss xmm2, xmm9
    jae 2f
    inc ecx                                 # x1i
2:  mov edx, r8d
    imul edx, dword ptr [rip+ra_sbytes]
    lea rsi, [rip+g_acc]
    mov edx, edx
    add rdx, rsi                            # début de la ligne
    lea r11d, [rax+1]
    cmp ecx, r11d
    jg .Lre_wide
    movaps xmm2, xmm0                       # cas étroit
    addss xmm2, xmm6
    mulss xmm2, dword ptr [rip+k_fhalf]
    cvtsi2ss xmm8, eax
    subss xmm2, xmm8                        # xmf
    mulss xmm2, xmm7                        # d * xmf
    movaps xmm8, xmm7
    subss xmm8, xmm2
    ACC [rdx+rax*4], xmm8
    ACC [rdx+rax*4+4], xmm2
    jmp .Lre_next
.Lre_wide:
    movaps xmm10, xmm9
    subss xmm10, xmm8
    movss xmm11, dword ptr [rip+k_f1]
    divss xmm11, xmm10                      # s
    cvtsi2ss xmm10, eax
    movaps xmm2, xmm8
    subss xmm2, xmm10                       # x0f
    movss xmm10, dword ptr [rip+k_f1]
    subss xmm10, xmm2
    mulss xmm10, xmm10
    mulss xmm10, xmm11
    mulss xmm10, dword ptr [rip+k_fhalf]    # a0
    cvtsi2ss xmm8, ecx
    subss xmm9, xmm8
    addss xmm9, dword ptr [rip+k_f1]
    mulss xmm9, xmm9
    mulss xmm9, xmm11
    mulss xmm9, dword ptr [rip+k_fhalf]     # am
    movaps xmm8, xmm7
    mulss xmm8, xmm10
    ACC [rdx+rax*4], xmm8
    lea r11d, [rax+2]
    cmp ecx, r11d
    jne .Lre_many
    movss xmm8, dword ptr [rip+k_f1]
    subss xmm8, xmm10
    subss xmm8, xmm9
    mulss xmm8, xmm7
    ACC [rdx+rax*4+4], xmm8
    jmp .Lre_tail
.Lre_many:
    movss xmm8, dword ptr [rip+k_f15]
    subss xmm8, xmm2
    mulss xmm8, xmm11                       # a1
    movaps xmm2, xmm8
    subss xmm2, xmm10
    mulss xmm2, xmm7
    ACC [rdx+rax*4+4], xmm2
    movaps xmm2, xmm7
    mulss xmm2, xmm11                       # d * s
    lea r11d, [rax+2]
    lea esi, [rcx-2]
.Lre_mid:
    cmp r11d, esi
    jg .Lre_midend
    ACC [rdx+r11*4], xmm2
    inc r11d
    jmp .Lre_mid
.Lre_midend:
    mov r11d, ecx
    sub r11d, eax
    sub r11d, 3
    cvtsi2ss xmm2, r11d
    mulss xmm2, xmm11
    addss xmm2, xmm8                        # a2
    movss xmm8, dword ptr [rip+k_f1]
    subss xmm8, xmm2
    subss xmm8, xmm9
    mulss xmm8, xmm7
    ACC [rdx+rcx*4-4], xmm8
.Lre_tail:
    movaps xmm8, xmm9
    mulss xmm8, xmm7
    ACC [rdx+rcx*4], xmm8
.Lre_next:
    movaps xmm0, xmm6
    inc r8d
    jmp .Lre_row
.Lre_ret:
    ret

# rast_poly : rsi = points flottants (x,y), ecx = n, edx = COLORREF, r8d = alpha (0..255)
#             écrit dans la fenêtre 1x (g_smallbits), limité au rectangle g_cl/g_ct/g_cr/g_cb
rast_poly:
    ENTER
    movups xmmword ptr [rsp+0], xmm6
    movups xmmword ptr [rsp+16], xmm7
    movups xmmword ptr [rsp+32], xmm8
    movups xmmword ptr [rsp+48], xmm9
    movups xmmword ptr [rsp+64], xmm10
    movups xmmword ptr [rsp+80], xmm11
    movups xmmword ptr [rsp+96], xmm12
    mov r12, rsi
    mov r13d, ecx
    mov dword ptr [rip+ra_col], edx
    mov dword ptr [rip+ra_alpha], r8d
    cmp r13d, 3
    jb .Lrp_end
    movss xmm0, dword ptr [r12]
    movaps xmm1, xmm0
    movss xmm2, dword ptr [r12+4]
    movaps xmm3, xmm2
    mov ecx, 1
.Lrp_bb:
    movss xmm4, dword ptr [r12+rcx*8]
    minss xmm0, xmm4
    maxss xmm1, xmm4
    movss xmm4, dword ptr [r12+rcx*8+4]
    minss xmm2, xmm4
    maxss xmm3, xmm4
    inc ecx
    cmp ecx, r13d
    jb .Lrp_bb
    cvtsi2ss xmm4, dword ptr [rip+g_cr]
    comiss xmm0, xmm4
    jae .Lrp_end
    cvtsi2ss xmm4, dword ptr [rip+g_cl]
    comiss xmm4, xmm1
    jae .Lrp_end
    cvtsi2ss xmm4, dword ptr [rip+g_cb]
    comiss xmm2, xmm4
    jae .Lrp_end
    cvtsi2ss xmm4, dword ptr [rip+g_ct]
    comiss xmm4, xmm3
    jae .Lrp_end
    FLOORSS xmm0
    mov r14d, eax                           # x0
    CEILSS xmm1
    mov ebx, eax
    FLOORSS xmm2
    mov r15d, eax                           # y0
    CEILSS xmm3
    mov esi, eax
    sub ebx, r14d                           # largeur
    sub esi, r15d                           # hauteur
    cmp ebx, 1
    jl .Lrp_end
    cmp esi, 1
    jl .Lrp_end
    cmp ebx, RMAXW
    jg .Lrp_end
    cmp esi, RMAXH
    jg .Lrp_end
    mov dword ptr [rip+ra_x0], r14d
    mov dword ptr [rip+ra_y0], r15d
    mov dword ptr [rip+ra_w], ebx
    mov dword ptr [rip+ra_h], esi
    lea eax, [rbx+3]
    mov dword ptr [rip+ra_stride], eax
    shl eax, 2
    mov dword ptr [rip+ra_sbytes], eax
    cvtsi2ss xmm0, r14d
    movss dword ptr [rip+ra_x0f], xmm0
    cvtsi2ss xmm0, r15d
    movss dword ptr [rip+ra_y0f], xmm0
    xor r10d, r10d
.Lrp_e:
    lea eax, [r10+1]
    cmp eax, r13d
    jb 1f
    xor eax, eax
1:  movss xmm6, dword ptr [rip+ra_x0f]
    movss xmm7, dword ptr [rip+ra_y0f]
    movss xmm0, dword ptr [r12+r10*8]
    subss xmm0, xmm6
    movss xmm1, dword ptr [r12+r10*8+4]
    subss xmm1, xmm7
    movss xmm2, dword ptr [r12+rax*8]
    subss xmm2, xmm6
    movss xmm3, dword ptr [r12+rax*8+4]
    subss xmm3, xmm7
    call rast_edge
    inc r10d
    cmp r10d, r13d
    jb .Lrp_e
    # --- résolution : sommes cumulées -> couverture -> mélange ---
    mov eax, dword ptr [rip+g_cl]
    sub eax, dword ptr [rip+ra_x0]
    jge 2f
    xor eax, eax
2:  mov dword ptr [rip+ra_xs], eax
    mov eax, dword ptr [rip+g_cr]
    sub eax, dword ptr [rip+ra_x0]
    cmp eax, dword ptr [rip+ra_w]
    jle 3f
    mov eax, dword ptr [rip+ra_w]
3:  mov dword ptr [rip+ra_xe], eax
    mov eax, dword ptr [rip+ra_col]
    movzx ecx, al
    mov dword ptr [rip+ra_r], ecx
    mov edx, eax
    shr edx, 8
    movzx ecx, dl
    mov dword ptr [rip+ra_g], ecx
    shr eax, 16
    movzx ecx, al
    mov dword ptr [rip+ra_b], ecx
    mov eax, dword ptr [rip+ra_r]
    shl eax, 16
    mov ecx, dword ptr [rip+ra_g]
    shl ecx, 8
    or eax, ecx
    or eax, dword ptr [rip+ra_b]
    mov dword ptr [rip+ra_pix], eax
    cvtsi2ss xmm8, dword ptr [rip+ra_alpha]
    mulss xmm8, dword ptr [rip+k_f256_255]
    xor r8d, r8d                            # ligne
.Lrp_row:
    cmp r8d, dword ptr [rip+ra_h]
    jge .Lrp_end
    mov edx, r8d
    imul edx, dword ptr [rip+ra_sbytes]
    lea r10, [rip+g_acc]
    mov edx, edx
    add rdx, r10                            # ligne de g_acc
    mov eax, dword ptr [rip+ra_y0]
    add eax, r8d                            # y absolu
    cmp eax, dword ptr [rip+g_ct]
    jl .Lrp_skip
    cmp eax, dword ptr [rip+g_cb]
    jge .Lrp_skip
    imul eax, eax, WW
    add eax, dword ptr [rip+ra_x0]
    add eax, dword ptr [rip+ra_xs]
    mov rdi, qword ptr [rip+g_smallbits]
    lea rdi, [rdi+rax*4]
    xorps xmm0, xmm0
    xor ecx, ecx
.Lrp_p1:
    cmp ecx, dword ptr [rip+ra_xs]
    jge .Lrp_p2
    movss xmm1, dword ptr [rdx+rcx*4]
    addss xmm0, xmm1
    mov dword ptr [rdx+rcx*4], 0
    inc ecx
    jmp .Lrp_p1
.Lrp_p2:
    cmp ecx, dword ptr [rip+ra_xe]
    jge .Lrp_p4
    movss xmm1, dword ptr [rdx+rcx*4]
    mov dword ptr [rdx+rcx*4], 0
    addss xmm0, xmm1
    movaps xmm2, xmm0
    andps xmm2, xmmword ptr [rip+k_absmask_ps]
    minss xmm2, dword ptr [rip+k_f1]
    mulss xmm2, xmm8
    cvtss2si eax, xmm2                      # opacité 0..256
    test eax, eax
    jz .Lrp_pn
    cmp eax, 256
    jl .Lrp_blend
    mov r9d, dword ptr [rip+ra_pix]
    mov dword ptr [rdi], r9d
    jmp .Lrp_pn
.Lrp_blend:
    mov r10d, 256
    sub r10d, eax
    mov r9d, dword ptr [rdi]
    movzx r11d, r9b                         # bleu
    imul r11d, r10d
    mov ebx, dword ptr [rip+ra_b]
    imul ebx, eax
    add r11d, ebx
    shr r11d, 8
    mov esi, r11d
    mov r11d, r9d                           # vert
    shr r11d, 8
    movzx r11d, r11b
    imul r11d, r10d
    mov ebx, dword ptr [rip+ra_g]
    imul ebx, eax
    add r11d, ebx
    shr r11d, 8
    shl r11d, 8
    or esi, r11d
    mov r11d, r9d                           # rouge
    shr r11d, 16
    movzx r11d, r11b
    imul r11d, r10d
    mov ebx, dword ptr [rip+ra_r]
    imul ebx, eax
    add r11d, ebx
    shr r11d, 8
    shl r11d, 16
    or esi, r11d
    mov dword ptr [rdi], esi
.Lrp_pn:
    add rdi, 4
    inc ecx
    jmp .Lrp_p2
.Lrp_p4:
    mov esi, dword ptr [rip+ra_w]
.Lrp_p5:
    cmp ecx, esi
    jge .Lrp_p6
    mov dword ptr [rdx+rcx*4], 0
    inc ecx
    jmp .Lrp_p5
.Lrp_p6:
    mov dword ptr [rdx+rsi*4], 0
    mov dword ptr [rdx+rsi*4+4], 0
    mov dword ptr [rdx+rsi*4+8], 0
    inc r8d
    jmp .Lrp_row
.Lrp_skip:
    mov rdi, rdx
    mov ecx, dword ptr [rip+ra_stride]
    xor eax, eax
    rep stosd
    inc r8d
    jmp .Lrp_row
.Lrp_end:
    movups xmm6, xmmword ptr [rsp+0]
    movups xmm7, xmmword ptr [rsp+16]
    movups xmm8, xmmword ptr [rsp+32]
    movups xmm9, xmmword ptr [rsp+48]
    movups xmm10, xmmword ptr [rsp+64]
    movups xmm11, xmmword ptr [rsp+80]
    movups xmm12, xmmword ptr [rsp+96]
    LEAVE

# ---------- ombres : enveloppe convexe des 8 coins projetés ----------

# hull8 : 8 points dans g_pts / g_pts+PTSF_OFF -> enveloppe convexe recopiée aux emplacements 0..k-1, eax = k
hull8:
    push rbx
    lea rsi, [rip+g_pts+PTSF_OFF]
    xor ebx, ebx
    movss xmm0, dword ptr [rsi]
    mov ecx, 1
1:  movss xmm1, dword ptr [rsi+rcx*8]
    comiss xmm1, xmm0
    jae 2f
    movaps xmm0, xmm1
    mov ebx, ecx
2:  inc ecx
    cmp ecx, 8
    jb 1b
    mov r8d, ebx                            # départ
    mov r9d, ebx                            # courant
    xor r10d, r10d                          # taille
.Lh_wrap:
    lea rax, [rip+g_hull]
    mov byte ptr [rax+r10], r9b
    inc r10d
    lea eax, [r9+1]
    and eax, 7
    mov r11d, eax                           # candidat suivant
    xor ecx, ecx
.Lh_j:
    cmp ecx, r9d
    je .Lh_jn
    movss xmm0, dword ptr [rsi+r9*8]
    movss xmm1, dword ptr [rsi+r9*8+4]
    movss xmm2, dword ptr [rsi+r11*8]
    subss xmm2, xmm0
    movss xmm3, dword ptr [rsi+r11*8+4]
    subss xmm3, xmm1
    movss xmm4, dword ptr [rsi+rcx*8]
    subss xmm4, xmm0
    movss xmm5, dword ptr [rsi+rcx*8+4]
    subss xmm5, xmm1
    mulss xmm2, xmm5
    mulss xmm3, xmm4
    subss xmm2, xmm3                        # produit vectoriel
    xorps xmm0, xmm0
    comiss xmm2, xmm0
    jae .Lh_jn
    mov r11d, ecx
.Lh_jn:
    inc ecx
    cmp ecx, 8
    jb .Lh_j
    mov r9d, r11d
    cmp r9d, r8d
    je .Lh_done
    cmp r10d, 8
    jb .Lh_wrap
.Lh_done:
    lea rsi, [rip+g_pts]
    xor ecx, ecx
.Lh_cp:
    lea rax, [rip+g_hull]
    movzx edx, byte ptr [rax+rcx]
    mov r8, qword ptr [rsi+rdx*8]
    mov r9, qword ptr [rsi+rdx*8+PTSF_OFF]
    lea r11d, [rcx+8]
    mov qword ptr [rsi+r11*8], r8
    mov qword ptr [rsi+r11*8+PTSF_OFF], r9
    inc ecx
    cmp ecx, r10d
    jb .Lh_cp
    xor ecx, ecx
.Lh_back:
    lea r11d, [rcx+8]
    mov r8, qword ptr [rsi+r11*8]
    mov r9, qword ptr [rsi+r11*8+PTSF_OFF]
    mov qword ptr [rsi+rcx*8], r8
    mov qword ptr [rsi+rcx*8+PTSF_OFF], r9
    inc ecx
    cmp ecx, r10d
    jb .Lh_back
    mov eax, r10d
    pop rbx
    ret

# draw_die_shadow : rdi = dé. Ombre portée = enveloppe convexe des 8 coins projetés sur le tapis
draw_die_shadow:
    ENTER
    mov rbx, rdi
    mov rax, qword ptr [rbx+D_P]
    mov qword ptr [rip+g_P], rax
    mov rax, qword ptr [rbx+D_P+8]
    mov qword ptr [rip+g_P+8], rax
    mov rax, qword ptr [rbx+D_P+16]
    mov qword ptr [rip+g_P+16], rax
    xor r12d, r12d
    call calc_face                  # repère de la face 1 : (n, a, b) -> les 8 coins
    xor r13d, r13d
.Lds_c:
    lea rax, [rip+k_cube8]
    imul ecx, r13d, 24
    movsd xmm0, qword ptr [rax+rcx]
    movsd xmm1, qword ptr [rax+rcx+8]
    movsd xmm2, qword ptr [rax+rcx+16]
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
    cmp r13d, 8
    jb .Lds_c
    call hull8
    mov dword ptr [rip+pp_n], eax
    mov dword ptr [rip+pp_edge], -1
    mov eax, C_SHADOW
    mov ecx, 255
    cmp dword ptr [rip+g_be], 0
    je 1f
    xor eax, eax                    # modes lissés : ombre noire translucide
    mov ecx, 100
1:  mov dword ptr [rip+pp_fill], eax
    mov dword ptr [rip+pp_alpha], ecx
    call prim_poly
    mov dword ptr [rip+pp_alpha], 255
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
    mov dword ptr [rip+pp_fill], eax
    mov eax, C_EDGE
    cmp dword ptr [rbx+D_HELD], 0
    je 7f
    mov eax, C_GOLD
7:  mov dword ptr [rip+pp_edge], eax
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
    mov dword ptr [rip+pp_n], 4
    call prim_poly
    # points
    lea rax, [rip+k_pipmask]
    movzx r13d, word ptr [rax+r12*2]
    mov eax, C_PIP
    test r12d, r12d
    jnz 1f
    mov eax, C_PIPRED
1:  mov dword ptr [rip+pp_fill], eax
    mov dword ptr [rip+pp_edge], -1
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
    mov dword ptr [rip+pp_n], 12
    call prim_poly
.Lpip_next:
    inc r14d
    cmp r14d, 9
    jb .Lpip
.Lface_next:
    inc r12d
    cmp r12d, 6
    jb .Lface
    LEAVE

# draw_dice_all : disques des dés sélectionnés, ombres, puis les six dés du plus loin au plus proche
draw_dice_all:
    ENTER
    xor r12d, r12d
.Ldd_ring:
    imul eax, r12d, DSTRIDE
    lea rbx, [rip+g_dice]
    add rbx, rax
    cmp dword ptr [rbx+D_HELD], 0
    je .Ldd_rnext
    mov dword ptr [rip+pp_fill], C_HELDDISC
    mov dword ptr [rip+pp_edge], C_GOLD
    mov dword ptr [rip+pp_alpha], 255
    movsd xmm0, qword ptr [rbx+D_AX]
    movsd xmm1, qword ptr [rbx+D_BY]
    movsd xmm2, qword ptr [rip+k_felt]
    movsd xmm3, qword ptr [rip+k_heldr]
    call prim_ground_ellipse
    mov dword ptr [rip+pp_edge], -1
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

# ---------- interface sur le décor : étiquettes et texte ----------

draw_labels:
    ENTER
    xor ecx, ecx
    call sel_fontk
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
    xor ecx, ecx
    call msg_lbl
    mov eax, dword ptr [rip+g_ptok]
    call msg_num
    lea rsi, [rip+g_lbl]
    xorpd xmm0, xmm0
    movsd xmm1, qword ptr [rip+k_toilz]
    call draw_ground_text
    lea rdi, [rip+g_lbl]
    call msg_start
    mov ecx, 1
    call msg_lbl
    mov eax, dword ptr [rip+g_btok]
    call msg_num
    lea rsi, [rip+g_lbl]
    xorpd xmm0, xmm0
    movsd xmm1, qword ptr [rip+k_botlz]
    call draw_ground_text
    LEAVE

# draw_hud : titre, numéro de manche, messages (coordonnées 1x)
draw_hud:
    ENTER
    mov ecx, 1
    call sel_fontk
    mov ecx, C_GOLD
    call set_txt
    mov ecx, 20
    mov edx, 3
    lea r8, [rip+s_h1]
    xor r9d, r9d
    call draw_flat
    mov ecx, 2
    call sel_fontk
    mov ecx, C_WHITE
    call set_txt
    lea rdi, [rip+g_lbl]
    call msg_start
    lea rsi, [rip+t_manche]
    call msg_str
    mov eax, dword ptr [rip+g_round]
    call msg_num
    cmp dword ptr [rip+g_twop], 0
    je 1f
    lea rsi, [rip+t_sep]
    call msg_str
    lea rsi, [rip+t_m2p]
    cmp dword ptr [rip+g_twop], 2
    jne 3f
    lea rsi, [rip+n_online]
3:  call msg_str
    jmp 2f
1:  lea rsi, [rip+t_sep]
    call msg_str
    lea rsi, [rip+t_bot2]
    call msg_str
    lea rdx, [rip+lv_names]
    mov eax, dword ptr [rip+g_level]
    mov rsi, qword ptr [rdx+rax*8]
    call msg_str
    lea rsi, [rip+t_sep]
    call msg_str
    mov eax, dword ptr [rip+g_wins]
    call msg_num
    lea rsi, [rip+t_dash]
    call msg_str
    mov eax, dword ptr [rip+g_losses]
    call msg_num
2:  mov ecx, WW-20
    mov edx, 17
    lea r8, [rip+g_lbl]
    mov r9d, 2                      # TA_RIGHT
    call draw_flat
    mov ecx, 20
    mov edx, 62
    lea r8, [rip+g_line1]
    xor r9d, r9d
    call draw_flat
    mov ecx, C_GOLD
    call set_txt
    mov ecx, 20
    mov edx, 98
    lea r8, [rip+g_line2]
    xor r9d, r9d
    call draw_flat
    mov ecx, 3                              # rappel des touches, discret, en bas à gauche
    call sel_fontk
    mov ecx, C_HINT
    call set_txt
    mov ecx, 20
    mov edx, WH-38
    lea r8, [rip+t_hint]
    xor r9d, r9d
    call draw_flat
    LEAVE

# rebuild_bg1 : décor propre + étiquettes + texte, en 1x
rebuild_bg1:
    ENTER
    mov rsi, qword ptr [rip+g_bgbits]
    mov rdi, qword ptr [rip+g_bg1bits]
    mov ecx, WW*WH*4/8
    cld
    rep movsq
    mov ecx, 2
    call set_target
    call draw_labels
    call draw_hud
    call GdiFlush
    LEAVE

# build_bg : rend la table en 2x (GDI) puis la réduit dans g_bgbits (décor propre, 1x)
build_bg:
    ENTER
    lea rcx, [rip+g_q0]
    call QueryPerformanceCounter
    mov r12d, dword ptr [rip+g_be]
    mov dword ptr [rip+g_be], 0
    xor ecx, ecx
    call set_target
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
    call GdiFlush
    mov rdi, qword ptr [rip+g_bgbits]
    xor ecx, ecx
    xor edx, edx
    mov r8d, WW
    mov r9d, WH
    call downsample_rect
    mov dword ptr [rip+g_be], r12d
    lea rcx, [rip+g_q1]
    call QueryPerformanceCounter
    mov rax, qword ptr [rip+g_q1]
    sub rax, qword ptr [rip+g_q0]
    mov qword ptr [rip+g_tbg], rax
    LEAVE

# ---------- copies et réductions de zones ----------

# downsample_rect : tampon 2x -> [rdi] (1x) sur le rectangle ecx,edx,r8d,r9d = x0,y0,x1,y1 (x multiples de 4)
downsample_rect:
    push rbx
    mov r10d, r8d
    sub r10d, ecx
    shr r10d, 2                             # blocs de 4 pixels par ligne
    mov r11d, r9d
    sub r11d, edx                           # lignes
    test r10d, r10d
    jz .Ldr_out
    test r11d, r11d
    jz .Ldr_out
    mov rsi, qword ptr [rip+g_bigbits]
    mov eax, edx
    add eax, eax
    imul eax, eax, BUFW
    lea eax, [rax+rcx*2]
    shl rax, 2
    add rsi, rax
    mov eax, edx
    imul eax, eax, WW
    add eax, ecx
    shl rax, 2
    add rdi, rax
.Ldr_row:
    lea r8, [rsi+BUFW*4]
    mov r9, rsi
    mov rax, rdi
    mov ecx, r10d
.Ldr_blk:
    movdqu xmm0, xmmword ptr [r9]
    movdqu xmm1, xmmword ptr [r8]
    pavgb xmm0, xmm1
    movdqu xmm2, xmmword ptr [r9+16]
    movdqu xmm3, xmmword ptr [r8+16]
    pavgb xmm2, xmm3
    pshufd xmm4, xmm0, 0x88
    pshufd xmm0, xmm0, 0xDD
    pavgb xmm0, xmm4
    pshufd xmm4, xmm2, 0x88
    pshufd xmm2, xmm2, 0xDD
    pavgb xmm2, xmm4
    punpcklqdq xmm0, xmm2
    movdqu xmmword ptr [rax], xmm0
    add r9, 32
    add r8, 32
    add rax, 16
    dec ecx
    jnz .Ldr_blk
    add rsi, BUFW*8
    add rdi, WW*4
    dec r11d
    jnz .Ldr_row
.Ldr_out:
    pop rbx
    ret

# restore2x : décor 1x (bg1) -> tampon 2x (chaque pixel doublé) sur le rectangle ecx,edx,r8d,r9d
restore2x:
    mov r10d, r8d
    sub r10d, ecx
    shr r10d, 2
    mov r11d, r9d
    sub r11d, edx
    test r10d, r10d
    jz .Lr2_out
    test r11d, r11d
    jz .Lr2_out
    mov rsi, qword ptr [rip+g_bg1bits]
    mov eax, edx
    imul eax, eax, WW
    add eax, ecx
    shl rax, 2
    add rsi, rax
    mov rdi, qword ptr [rip+g_bigbits]
    mov eax, edx
    add eax, eax
    imul eax, eax, BUFW
    lea eax, [rax+rcx*2]
    shl rax, 2
    add rdi, rax
.Lr2_row:
    mov r8, rsi
    mov r9, rdi
    mov ecx, r10d
.Lr2_blk:
    movdqu xmm0, xmmword ptr [r8]
    pshufd xmm1, xmm0, 0x50
    pshufd xmm2, xmm0, 0xFA
    movdqu xmmword ptr [r9], xmm1
    movdqu xmmword ptr [r9+16], xmm2
    movdqu xmmword ptr [r9+BUFW*4], xmm1
    movdqu xmmword ptr [r9+BUFW*4+16], xmm2
    add r8, 16
    add r9, 32
    dec ecx
    jnz .Lr2_blk
    add rsi, WW*4
    add rdi, BUFW*8
    dec r11d
    jnz .Lr2_row
.Lr2_out:
    ret

# restore1x : décor 1x (bg1) -> fenêtre 1x sur le rectangle ecx,edx,r8d,r9d
restore1x:
    mov r10d, r8d
    sub r10d, ecx
    shl r10d, 2
    shr r10d, 3                             # quadruplets par ligne
    mov r11d, r9d
    sub r11d, edx
    test r10d, r10d
    jz .Lr1_out
    test r11d, r11d
    jz .Lr1_out
    mov eax, edx
    imul eax, eax, WW
    add eax, ecx
    shl rax, 2
    mov rsi, qword ptr [rip+g_bg1bits]
    add rsi, rax
    mov rdi, qword ptr [rip+g_smallbits]
    add rdi, rax
    cld
.Lr1_row:
    push rsi
    push rdi
    mov ecx, r10d
    rep movsq
    pop rdi
    pop rsi
    add rsi, WW*4
    add rdi, WW*4
    dec r11d
    jnz .Lr1_row
.Lr1_out:
    ret

# ---------- zones modifiées ----------

# union_R : eax = l, ecx = t, edx = r, r8d = b -> agrandit g_R
union_R:
    cmp eax, dword ptr [rip+g_R]
    jge 1f
    mov dword ptr [rip+g_R], eax
1:  cmp ecx, dword ptr [rip+g_R+4]
    jge 2f
    mov dword ptr [rip+g_R+4], ecx
2:  cmp edx, dword ptr [rip+g_R+8]
    jle 3f
    mov dword ptr [rip+g_R+8], edx
3:  cmp r8d, dword ptr [rip+g_R+12]
    jle 4f
    mov dword ptr [rip+g_R+12], r8d
4:  ret

# die_bbox : rdi = dé. Ajoute à g_R l'ancienne et la nouvelle boîte (dé + ombre) en pixels de la fenêtre
die_bbox:
    push rbx
    mov rbx, rdi
    movsd xmm0, qword ptr [rbx+D_P]
    movsd xmm1, qword ptr [rbx+D_P+8]
    movsd xmm2, qword ptr [rbx+D_P+16]
    movapd xmm3, xmm0
    subsd xmm3, xmm1
    mulsd xmm3, qword ptr [rip+k_r0]
    mulsd xmm3, qword ptr [rip+k_fsc]
    addsd xmm3, qword ptr [rip+k_fcx]
    movapd xmm4, xmm0
    addsd xmm4, xmm1
    mulsd xmm4, qword ptr [rip+k_u0]
    movapd xmm5, xmm2
    mulsd xmm5, qword ptr [rip+k_u2]
    addsd xmm4, xmm5
    mulsd xmm4, qword ptr [rip+k_fsc]
    movsd xmm5, qword ptr [rip+k_fcy]
    subsd xmm5, xmm4
    movsd qword ptr [rip+bb_sx], xmm3
    movsd qword ptr [rip+bb_sy], xmm5
    movapd xmm3, xmm2                       # centre de l'ombre
    mulsd xmm3, qword ptr [rip+k_shx]
    addsd xmm3, xmm0
    movapd xmm4, xmm2
    mulsd xmm4, qword ptr [rip+k_shy]
    addsd xmm4, xmm1
    movapd xmm0, xmm3
    subsd xmm0, xmm4
    mulsd xmm0, qword ptr [rip+k_r0]
    mulsd xmm0, qword ptr [rip+k_fsc]
    addsd xmm0, qword ptr [rip+k_fcx]       # xmm0 = SX ombre
    addsd xmm3, xmm4
    mulsd xmm3, qword ptr [rip+k_u0]
    mulsd xmm3, qword ptr [rip+k_fsc]
    movsd xmm1, qword ptr [rip+k_fcy]
    subsd xmm1, xmm3                        # xmm1 = SY ombre
    movsd xmm2, qword ptr [rip+bb_sx]
    subsd xmm2, qword ptr [rip+k_bbr1]
    movapd xmm3, xmm0
    subsd xmm3, qword ptr [rip+k_bbr2]
    minsd xmm2, xmm3
    cvttsd2si eax, xmm2
    mov dword ptr [rip+bb_l], eax
    movsd xmm2, qword ptr [rip+bb_sy]
    subsd xmm2, qword ptr [rip+k_bbr1]
    movapd xmm3, xmm1
    subsd xmm3, qword ptr [rip+k_bbr2]
    minsd xmm2, xmm3
    cvttsd2si eax, xmm2
    mov dword ptr [rip+bb_t], eax
    movsd xmm2, qword ptr [rip+bb_sx]
    addsd xmm2, qword ptr [rip+k_bbr1]
    movapd xmm3, xmm0
    addsd xmm3, qword ptr [rip+k_bbr2]
    maxsd xmm2, xmm3
    cvttsd2si eax, xmm2
    inc eax
    mov dword ptr [rip+bb_r], eax
    movsd xmm2, qword ptr [rip+bb_sy]
    addsd xmm2, qword ptr [rip+k_bbr1]
    movapd xmm3, xmm1
    addsd xmm3, qword ptr [rip+k_bbr2]
    maxsd xmm2, xmm3
    cvttsd2si eax, xmm2
    inc eax
    mov dword ptr [rip+bb_b], eax
    cmp dword ptr [rip+bb_l], 0
    jge 1f
    mov dword ptr [rip+bb_l], 0
1:  cmp dword ptr [rip+bb_t], 0
    jge 2f
    mov dword ptr [rip+bb_t], 0
2:  cmp dword ptr [rip+bb_r], WW
    jle 3f
    mov dword ptr [rip+bb_r], WW
3:  cmp dword ptr [rip+bb_b], WH
    jle 4f
    mov dword ptr [rip+bb_b], WH
4:  cmp dword ptr [rbx+D_BBV], 0
    je 5f
    mov eax, dword ptr [rbx+D_BBL]
    mov ecx, dword ptr [rbx+D_BBT]
    mov edx, dword ptr [rbx+D_BBR]
    mov r8d, dword ptr [rbx+D_BBB]
    call union_R
5:  mov eax, dword ptr [rip+bb_l]
    mov ecx, dword ptr [rip+bb_t]
    mov edx, dword ptr [rip+bb_r]
    mov r8d, dword ptr [rip+bb_b]
    call union_R
    mov dword ptr [rbx+D_BBL], eax
    mov eax, dword ptr [rip+bb_l]
    mov dword ptr [rbx+D_BBL], eax
    mov eax, dword ptr [rip+bb_t]
    mov dword ptr [rbx+D_BBT], eax
    mov eax, dword ptr [rip+bb_r]
    mov dword ptr [rbx+D_BBR], eax
    mov eax, dword ptr [rip+bb_b]
    mov dword ptr [rbx+D_BBB], eax
    mov dword ptr [rbx+D_BBV], 1
    pop rbx
    ret

# ---------- image : composition de la zone modifiée ----------

# draw_dynamic : jetons, boutons, dés (du plus loin au plus proche) dans le tampon courant
draw_dynamic:
    ENTER
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
    LEAVE

# set_clip : ecx,edx,r8d,r9d = l,t,r,b dans le tampon courant (GDI et GDI+)
set_clip:
    ENTER
    mov r12d, ecx
    mov r13d, edx
    mov r14d, r8d
    mov r15d, r9d
    mov rcx, qword ptr [rip+g_hrgn]
    mov edx, r12d
    mov r8d, r13d
    mov r9d, r14d
    mov dword ptr [rsp+32], r15d
    call SetRectRgn
    mov rcx, qword ptr [rip+g_hdc]
    mov rdx, qword ptr [rip+g_hrgn]
    call SelectClipRgn
    cmp dword ptr [rip+g_be], 1
    jne 1f
    mov rcx, qword ptr [rip+g_gpg]
    mov edx, r12d
    mov r8d, r13d
    mov r9d, r14d
    sub r9d, r12d
    mov eax, r15d
    sub eax, r13d
    mov dword ptr [rsp+32], eax
    mov dword ptr [rsp+40], 0       # CombineModeReplace
    call qword ptr [rip+gpf+64]
1:  LEAVE

# render_frame : restaure le décor sur la zone modifiée, redessine, réduit si besoin
render_frame:
    ENTER
    lea rcx, [rip+g_q0]
    call QueryPerformanceCounter
    xor r12d, r12d                          # 1 = image complète
    cmp dword ptr [rip+g_full], 0
    je .Lrf_part
    call rebuild_bg1
    mov dword ptr [rip+g_cR], 0
    mov dword ptr [rip+g_cR+4], 0
    mov dword ptr [rip+g_cR+8], WW
    mov dword ptr [rip+g_cR+12], WH
    mov r12d, 1
    jmp .Lrf_go
.Lrf_part:
    mov eax, dword ptr [rip+g_R]
    and eax, -4
    mov ecx, dword ptr [rip+g_R+4]
    mov edx, dword ptr [rip+g_R+8]
    add edx, 3
    and edx, -4
    mov r8d, dword ptr [rip+g_R+12]
    cmp edx, WW
    jle 1f
    mov edx, WW
1:  cmp r8d, WH
    jle 2f
    mov r8d, WH
2:  cmp eax, edx
    jge .Lrf_none
    cmp ecx, r8d
    jge .Lrf_none
    mov dword ptr [rip+g_cR], eax
    mov dword ptr [rip+g_cR+4], ecx
    mov dword ptr [rip+g_cR+8], edx
    mov dword ptr [rip+g_cR+12], r8d
.Lrf_go:
    mov dword ptr [rip+g_R], WW             # zone sale remise à vide
    mov dword ptr [rip+g_R+4], WH
    mov dword ptr [rip+g_R+8], 0
    mov dword ptr [rip+g_R+12], 0
    mov eax, dword ptr [rip+g_cR]
    mov dword ptr [rip+g_cl], eax
    mov eax, dword ptr [rip+g_cR+4]
    mov dword ptr [rip+g_ct], eax
    mov eax, dword ptr [rip+g_cR+8]
    mov dword ptr [rip+g_cr], eax
    mov eax, dword ptr [rip+g_cR+12]
    mov dword ptr [rip+g_cb], eax
    cmp dword ptr [rip+g_mode], 0
    jne .Lrf_1x
    xor ecx, ecx                            # mode Haute : tampon 2x
    call set_target
    mov ecx, dword ptr [rip+g_cR]
    mov edx, dword ptr [rip+g_cR+4]
    mov r8d, dword ptr [rip+g_cR+8]
    mov r9d, dword ptr [rip+g_cR+12]
    call restore2x
    test r12d, r12d
    jnz 3f
    mov ecx, dword ptr [rip+g_cR]
    add ecx, ecx
    mov edx, dword ptr [rip+g_cR+4]
    add edx, edx
    mov r8d, dword ptr [rip+g_cR+8]
    add r8d, r8d
    mov r9d, dword ptr [rip+g_cR+12]
    add r9d, r9d
    call set_clip
    jmp 4f
3:  mov rcx, qword ptr [rip+g_hdc]
    xor edx, edx
    call SelectClipRgn
4:  call draw_dynamic
    call GdiFlush
    mov rdi, qword ptr [rip+g_smallbits]
    mov ecx, dword ptr [rip+g_cR]
    mov edx, dword ptr [rip+g_cR+4]
    mov r8d, dword ptr [rip+g_cR+8]
    mov r9d, dword ptr [rip+g_cR+12]
    call downsample_rect
    jmp .Lrf_fin
.Lrf_1x:
    mov ecx, 1                              # modes 1x : directement dans la fenêtre
    call set_target
    mov ecx, dword ptr [rip+g_cR]
    mov edx, dword ptr [rip+g_cR+4]
    mov r8d, dword ptr [rip+g_cR+8]
    mov r9d, dword ptr [rip+g_cR+12]
    call restore1x
    mov ecx, dword ptr [rip+g_cR]
    mov edx, dword ptr [rip+g_cR+4]
    mov r8d, dword ptr [rip+g_cR+8]
    mov r9d, dword ptr [rip+g_cR+12]
    call set_clip
    call draw_dynamic
    call sync_prims
    call GdiFlush
.Lrf_fin:
    mov dword ptr [rip+g_full], 0
    mov dword ptr [rip+g_dirty], 0
    lea rcx, [rip+g_q1]
    call QueryPerformanceCounter
    mov rax, qword ptr [rip+g_q1]
    sub rax, qword ptr [rip+g_q0]
    mov qword ptr [rip+g_tfr], rax
    inc dword ptr [rip+g_frames]
    mov rdi, rax
    call adapt_quality
    LEAVE
.Lrf_none:
    mov dword ptr [rip+g_dirty], 0
    mov dword ptr [rip+g_full], 0
    LEAVE

# ---------- modes de qualité ----------

# adapt_quality : rdi = durée de l'image (ticks QPC). Pendant les lancers, descend d'un mode si trop lent
adapt_quality:
    ENTER
    cmp dword ptr [rip+g_auto], 0
    je .Laq_end
    cmp dword ptr [rip+g_rolling], 0
    je .Laq_end
    add qword ptr [rip+g_sumdt], rdi
    inc dword ptr [rip+g_cnt]
    cmp dword ptr [rip+g_cnt], 24
    jb .Laq_end
    mov rax, qword ptr [rip+g_sumdt]
    xor edx, edx
    mov ecx, 24
    div rcx
    mov qword ptr [rip+g_sumdt], 0
    mov dword ptr [rip+g_cnt], 0
    mov ecx, dword ptr [rip+g_mode]
    cmp ecx, 3
    jb .Laq_cmp
    cmp rax, qword ptr [rip+g_budget_eco]   # Éco : on ne peut plus descendre
    jbe .Laq_end
    call goto_terminal
    jmp .Laq_end
.Laq_cmp:
    cmp rax, qword ptr [rip+g_budget]
    jbe .Laq_end
    cmp ecx, 2
    jae 1f
    mov ecx, 2                              # Haute / GDI+  ->  Rapide
    jmp 2f
1:  mov ecx, 3                              # Rapide -> Eco
2:  call set_mode
.Laq_end:
    LEAVE

# goto_terminal : demande à la fenêtre de passer en mode terminal (message traité hors du rendu)
goto_terminal:
    sub rsp, 40
    cmp dword ptr [rip+g_toterm], 0
    jne 1f
    mov dword ptr [rip+g_toterm], 1
    mov rcx, qword ptr [rip+g_hwnd]
    mov edx, 0x400                  # WM_USER
    xor r8d, r8d
    xor r9d, r9d
    call PostMessageA
1:  add rsp, 40
    ret

# set_mode : ecx = mode 0..3
set_mode:
    ENTER
    mov r12d, ecx
    cmp r12d, 1
    jne 1f
    call gp_ensure
    cmp qword ptr [rip+g_gpg], 0
    jne 1f
    mov r12d, 2                             # GDI+ indisponible -> mode Rapide
1:  mov dword ptr [rip+g_mode], r12d
    test r12d, r12d
    jnz 2f
    call alloc_big
    jmp 3f
2:  call free_big
3:  lea rax, [rip+be_of_mode]
    mov eax, dword ptr [rax+r12*4]
    mov dword ptr [rip+g_be], eax
    lea rax, [rip+int_of_mode]
    mov eax, dword ptr [rax+r12*4]
    mov dword ptr [rip+g_interval], eax
    cmp dword ptr [rip+g_tmr], 0
    je 4f
    call kill_timer
    call ensure_timer
4:  mov dword ptr [rip+g_full], 1
    mov dword ptr [rip+g_dirty], 1
    mov qword ptr [rip+g_sumdt], 0
    mov dword ptr [rip+g_cnt], 0
    mov rcx, qword ptr [rip+g_hwnd]
    lea rax, [rip+t_modes]
    mov rdx, qword ptr [rax+r12*8]
    call SetWindowTextA
    LEAVE

# ---------- minuterie à la demande ----------
ensure_timer:
    sub rsp, 40
    cmp dword ptr [rip+g_tmr], 0
    jne 1f
    mov rcx, qword ptr [rip+g_hwnd]
    mov edx, 1
    mov r8d, dword ptr [rip+g_interval]
    xor r9d, r9d
    call SetTimer
    mov dword ptr [rip+g_tmr], 1
1:  add rsp, 40
    ret

kill_timer:
    sub rsp, 40
    cmp dword ptr [rip+g_tmr], 0
    je 1f
    mov rcx, qword ptr [rip+g_hwnd]
    mov edx, 1
    call KillTimer
    mov dword ptr [rip+g_tmr], 0
1:  add rsp, 40
    ret

# ---------- initialisation graphique ----------
init_gfx:
    ENTER
    mov rcx, qword ptr [rip+g_hwnd]
    call GetDC
    mov r12, rax
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
    mov rcx, r12                    # fenêtre 1x
    call CreateCompatibleDC
    mov qword ptr [rip+g_hdcSmall], rax
    mov qword ptr [rip+g_dcs+8], rax
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
    mov rcx, qword ptr [rip+g_hdcSmall]
    call init_dc
    mov rcx, r12                    # décor + texte 1x
    call CreateCompatibleDC
    mov qword ptr [rip+g_hdcBg1], rax
    mov qword ptr [rip+g_dcs+16], rax
    mov rcx, r12
    lea rdx, [rip+g_bmiSmall]
    xor r8d, r8d
    lea r9, [rip+g_bg1bits]
    mov qword ptr [rsp+32], 0
    mov dword ptr [rsp+40], 0
    call CreateDIBSection
    mov rcx, qword ptr [rip+g_hdcBg1]
    mov rdx, rax
    call SelectObject
    mov rcx, qword ptr [rip+g_hdcBg1]
    call init_dc
    mov rcx, r12                    # décor propre (sans DC)
    lea rdx, [rip+g_bmiSmall]
    xor r8d, r8d
    lea r9, [rip+g_bgbits]
    mov qword ptr [rsp+32], 0
    mov dword ptr [rsp+40], 0
    call CreateDIBSection
    mov qword ptr [rip+g_hbmBg], rax
    mov rcx, qword ptr [rip+g_hwnd]
    mov rdx, r12
    call ReleaseDC
    cmp qword ptr [rip+g_smallbits], 0      # tampons indisponibles : repli en terminal
    je .Lig_fail
    cmp qword ptr [rip+g_bg1bits], 0
    je .Lig_fail
    cmp qword ptr [rip+g_bgbits], 0
    je .Lig_fail
    # polices : jeu 2x (indices 0-3) puis jeu 1x (4-7) : étiquettes, titre, messages, boutons
    lea r13, [rip+g_fonts]
    mov ecx, -80
    mov edx, 700
    call mkfont
    mov qword ptr [r13], rax
    mov ecx, -84
    mov edx, 700
    call mkfont
    mov qword ptr [r13+8], rax
    mov ecx, -60
    mov edx, 600
    call mkfont
    mov qword ptr [r13+16], rax
    mov ecx, -46
    mov edx, 700
    call mkfont
    mov qword ptr [r13+24], rax
    mov ecx, -40
    mov edx, 700
    call mkfont
    mov qword ptr [r13+32], rax
    mov ecx, -42
    mov edx, 700
    call mkfont
    mov qword ptr [r13+40], rax
    mov ecx, -30
    mov edx, 600
    call mkfont
    mov qword ptr [r13+48], rax
    mov ecx, -23
    mov edx, 700
    call mkfont
    mov qword ptr [r13+56], rax
    xor ecx, ecx                    # région de clip réutilisable
    xor edx, edx
    xor r8d, r8d
    xor r9d, r9d
    call CreateRectRgn
    mov qword ptr [rip+g_hrgn], rax
    lea rcx, [rip+g_qpf]
    call QueryPerformanceFrequency
    mov rax, qword ptr [rip+g_qpf]
    imul rax, rax, 12
    xor edx, edx
    mov ecx, 1000
    div rcx
    mov qword ptr [rip+g_budget], rax       # budget : 12 ms par image
    mov rax, qword ptr [rip+g_qpf]
    imul rax, rax, 30
    xor edx, edx
    mov ecx, 1000
    div rcx
    mov qword ptr [rip+g_budget_eco], rax   # Éco : 30 ms par image, sinon terminal
    rdtsc
    shl rdx, 32
    or rax, rdx
    or rax, 1
    mov qword ptr [rip+g_rng], rax
    call alloc_big
    cmp qword ptr [rip+g_bigbits], 0
    je .Lig_fail
    call build_bg                           # décor : rendu une fois
    xor r12d, r12d                          # mode de départ selon la vitesse du rendu du décor
    mov rax, qword ptr [rip+g_qpf]
    imul rax, rax, 60
    xor edx, edx
    mov ecx, 1000
    div rcx
    cmp qword ptr [rip+g_tbg], rax
    jbe 1f
    mov r12d, 2                             # machine lente : mode Rapide
    mov rax, qword ptr [rip+g_qpf]
    imul rax, rax, 200
    xor edx, edx
    mov ecx, 1000
    div rcx
    cmp qword ptr [rip+g_tbg], rax
    jbe 1f
    mov r12d, 3                             # très lente : mode Eco
    mov rax, qword ptr [rip+g_qpf]
    imul rax, rax, 800
    xor edx, edx
    mov ecx, 1000
    div rcx
    cmp qword ptr [rip+g_tbg], rax
    ja .Lig_fail                            # même le décor est trop lent : terminal
1:  cmp dword ptr [rip+g_optmode], 0         # mode choisi à la session précédente
    je .Lig_mode
    mov r12d, dword ptr [rip+g_optmode]
    dec r12d
    mov dword ptr [rip+g_auto], 0
.Lig_mode:
    mov ecx, r12d
    call set_mode
    call init_dice
    call new_game
    LEAVE
.Lig_fail:
    mov dword ptr [rip+g_gfxfail], 1
    LEAVE

# toggle_fullscreen : F11. Bordure retirée, fenêtre étendue à l'écran, jeu centré en 1:1 sur fond noir
#                     (aucune mise à l'échelle : même coût par image qu'en fenêtre)
toggle_fullscreen:
    ENTER
    cmp dword ptr [rip+g_fsmode], 0
    jne .Ltf_off
    mov rcx, qword ptr [rip+g_hwnd]
    lea rdx, [rip+g_wrect]
    call GetWindowRect
    mov rcx, qword ptr [rip+g_hwnd]
    mov edx, -16                            # GWL_STYLE
    mov r8d, 0x90000000                     # WS_POPUP | WS_VISIBLE
    call SetWindowLongA
    xor ecx, ecx                            # SM_CXSCREEN
    call GetSystemMetrics
    mov r12d, eax
    mov ecx, 1                              # SM_CYSCREEN
    call GetSystemMetrics
    mov r13d, eax
    mov rcx, qword ptr [rip+g_hwnd]
    xor edx, edx
    xor r8d, r8d
    xor r9d, r9d
    mov dword ptr [rsp+32], r12d
    mov dword ptr [rsp+40], r13d
    mov dword ptr [rsp+48], 0x60            # SWP_FRAMECHANGED | SWP_SHOWWINDOW
    call SetWindowPos
    mov eax, r12d
    sub eax, WW
    sar eax, 1
    jns 1f
    xor eax, eax
1:  mov dword ptr [rip+g_ox], eax
    mov eax, r13d
    sub eax, WH
    sar eax, 1
    jns 2f
    xor eax, eax
2:  mov dword ptr [rip+g_oy], eax
    mov dword ptr [rip+g_fsmode], 1
    mov dword ptr [rip+g_erase], 1
    mov rcx, qword ptr [rip+g_hwnd]
    xor edx, edx
    mov r8d, 1                              # effacer en noir une seule fois
    call InvalidateRect
    jmp .Ltf_end
.Ltf_off:
    mov rcx, qword ptr [rip+g_hwnd]
    mov edx, -16
    mov r8d, 0x10CA0000                     # style fenêtre normal
    call SetWindowLongA
    mov rcx, qword ptr [rip+g_hwnd]
    xor edx, edx
    mov r8d, dword ptr [rip+g_wrect]
    mov r9d, dword ptr [rip+g_wrect+4]
    mov eax, dword ptr [rip+g_wrect+8]
    sub eax, r8d
    mov dword ptr [rsp+32], eax
    mov eax, dword ptr [rip+g_wrect+12]
    sub eax, r9d
    mov dword ptr [rsp+40], eax
    mov dword ptr [rsp+48], 0x60
    call SetWindowPos
    mov dword ptr [rip+g_ox], 0
    mov dword ptr [rip+g_oy], 0
    mov dword ptr [rip+g_fsmode], 0
    mov rcx, qword ptr [rip+g_hwnd]
    xor edx, edx
    xor r8d, r8d
    call InvalidateRect
.Ltf_end:
    mov dword ptr [rip+g_full], 1
    mov dword ptr [rip+g_dirty], 1
    LEAVE
