; SPDX-License-Identifier: NOASSERTION
;
; RDsave - save the RAM-disk to a real medium
;
; Authors: Mario79, Heavyiron, Lrz, Burer
;
; Offers the target of the save rule in save.inc. A file picked in the
; dialog is a one-time target; the ini keeps it only when the kernel knows
; no boot medium.

; ====================================================================

include "../../macros.inc"

format meos 01
entry START
stack 4096

include "../../proc32.inc"
include "../../dll.inc"
include "../../KOSfuncs.inc"
include "../../string.inc"

; ====================================================================

START:
        mcall   SF_SYS_MISC, SSF_HEAP_INIT

        stdcall dll.Load, importLib
        test    eax, eax
        jnz     exit

        mcall   SF_SYSTEM_GET, SSF_RD_BOOT_SOURCE
        mov     [boot_src], eax
        invoke  ini_get_int, ini_file, ini_sec, key_autoclose, 1
        mov     [autoclose], eax
        call    rd_read_path

        stdcall string.copy, default_name, filename_area
        push    dword OpenDialog_data
        call    [OpenDialog_Init]

        call    draw_window

        ; nothing to offer: ask at once
        call    has_boot_medium
        je      still
        cmp     byte [fname_buf], 0
        je      select
        jmp     still

; ====================================================================

redraw:
        call    draw_window

still:
        mcall   SF_WAIT_EVENT

        cmp     al, EV_REDRAW
        je      redraw
        cmp     al, EV_KEY
        je      key
        cmp     al, EV_BUTTON
        je      button

        jmp     still

; ====================================================================

key:
        mcall   SF_GET_KEY

        cmp     ah, KEY_ESC
        je      exit
        cmp     ah, KEY_ENTER
        je      save

        jmp     still

; ====================================================================

button:
        mcall   SF_GET_BUTTON

        cmp     ah, BTN_CLOSE
        je      exit
        cmp     ah, BTN_SAVE
        je      save
        cmp     ah, BTN_SELECT
        je      select
        cmp     ah, BTN_FLOPPY
        je      floppy

        jmp     still

exit:
        mcall   SF_TERMINATE_PROCESS

; ====================================================================

select:
        mov     [status_text], 0

        push    dword OpenDialog_data
        call    [OpenDialog_Start]

        cmp     [OpenDialog_data.status], OPENDIALOG_OK
        jne     redraw

        stdcall string.copy, dialog_path, fname_buf
        mov     [picked], 1
        jmp     redraw

floppy:
        call    show_saving

        mcall   SF_RD_TO_FLOPPY, FLOPPY_A
        test    eax, eax
        jz      report

        mov     eax, ERR_DEVICE
        jmp     report

save:
        call    show_saving
        call    do_save

; eax = the result of the save
report:
        test    eax, eax
        jz      .ok

        ; the rule found no target: ask
        cmp     eax, RD_ERR_NO_MEDIUM
        jne     .failed
        cmp     [picked], 0
        je      select

.failed:
        mov     eax, [err_msgs + eax*4]
        mov     [status_text], eax
        mov     [status_color], COLOR_ERROR
        call    draw_status
        jmp     still

.ok:
        mov     [status_text], msg_ok
        mov     [status_color], COLOR_OK
        call    draw_status

        cmp     [autoclose], 0
        je      still

        mcall   SF_SLEEP, CLOSE_DELAY
        jmp     exit

show_saving:
        mov     eax, [sc.work_text]
        mov     [status_text], msg_saving
        mov     [status_color], eax
        jmp     draw_status

; ====================================================================

include "save.inc"

; ZF if the kernel knows the boot medium
has_boot_medium:
        cmp     [boot_src], RD_LOAD_FROM_FLOPPY
        je      .done
        cmp     [boot_src], RD_LOAD_FROM_HD

.done:
        ret

; eax = the result code
do_save:
        cmp     [picked], 0
        jne     .picked

        call    rd_save
        jmp     .clamp

.picked:
        call    has_boot_medium
        je      .write

        ; before the save, so that the saved image has the path
        stdcall string.length, fname_buf
        invoke  ini_set_str, ini_file, ini_sec, key_path, fname_buf, eax

.write:
        mcall   SF_SYSTEM, SSF_RD_TO_HDD, fname_buf

.clamp:
        cmp     eax, ERR_DEVICE
        jbe     .done

        mov     eax, ERR_UNKNOWN

.done:
        ret

; ====================================================================

draw_window:
        mcall   SF_STYLE_SETTINGS, SSF_GET_COLORS, sc, sizeof.system_colors
        mcall   SF_REDRAW, SSF_BEGIN_DRAW

        mcall   SF_STYLE_SETTINGS, SSF_GET_SKIN_HEIGHT
        lea     ecx, [eax + (WINDOW_Y shl 16) + WINDOW_H]
        mov     edx, [sc.work]
        or      edx, WINDOW_STYLE
        mcall   SF_CREATE_WINDOW, <WINDOW_X, WINDOW_W>, , , 0, title

        mov     ecx, [sc.work_text]
        or      ecx, FONT
        mcall   SF_DRAW_TEXT, <GAP, TARGET_Y>, , lab_target
        call    draw_target

        mov     edi, buttons

.button:
        mov     ebx, [edi + BUTTON.x]
        shl     ebx, 16
        add     ebx, BTN_W
        movzx   edx, [edi + BUTTON.id]
        mcall   SF_DEFINE_BUTTON, , <BTN_Y, BTN_H>, , [sc.work_button]

        mov     ebx, [edi + BUTTON.x]
        add     ebx, GAP
        shl     ebx, 16
        add     ebx, BTN_Y + BTN_TEXT_DY
        mov     ecx, [sc.work_button_text]
        or      ecx, FONT
        mcall   SF_DRAW_TEXT, , , [edi + BUTTON.caption]

        add     edi, sizeof.BUTTON
        cmp     edi, buttons_end
        jb      .button

        call    draw_status

        mcall   SF_REDRAW, SSF_END_DRAW

        ret

; what the Save button writes to; a path is in cp866, not UTF-8
draw_target:
        cmp     [picked], 0
        jne     .path

        mov     edx, tgt_boot
        call    has_boot_medium
        je      .text

        mov     edx, tgt_none
        cmp     byte [fname_buf], 0
        je      .text

.path:
        mov     edx, fname_buf
        mov     ecx, FONT_CP866
        jmp     .draw

.text:
        mov     ecx, FONT

.draw:
        or      ecx, [sc.work_text]
        mcall   SF_DRAW_TEXT, <VALUE_X, TARGET_Y>

        ret

draw_status:
        mov     edx, [status_text]
        test    edx, edx
        jz      .done

        mcall   SF_DRAW_RECT, <GAP, CLIENT_W - 2*GAP>, <STATUS_Y, FONT_CHAR_H>, [sc.work]

        mov     ecx, [status_color]
        or      ecx, FONT
        mcall   SF_DRAW_TEXT, <GAP, STATUS_Y>, , [status_text]

.done:
        ret

; ====================================================================

; layout; BTN_W is after the captions
GAP         = 10
TARGET_Y    = GAP
VALUE_X     = GAP + (lab_target.chars + 1)*FONT_CHAR_W
BTN_Y       = TARGET_Y + FONT_CHAR_H + GAP
BTN_H       = 24
BTN_TEXT_DY = (BTN_H - FONT_CHAR_H)/2
BTN_COL1    = GAP
BTN_COL2    = BTN_COL1 + BTN_W + GAP
BTN_COL3    = BTN_COL2 + BTN_W + GAP
STATUS_Y    = BTN_Y + BTN_H + GAP

; window
CLIENT_W    = BTN_COL3 + BTN_W + GAP
CLIENT_H    = STATUS_Y + FONT_CHAR_H + GAP
WINDOW_X    = 200
WINDOW_Y    = 200
WINDOW_W    = CLIENT_W + 9                      ; borders 5 + 5, the kernel adds a pixel
WINDOW_H    = CLIENT_H + 4                      ; border 5, the same pixel; redraw adds the skin
WINDOW_STYLE = 0x34000000                       ; skinned, fixed size, caption, client coordinates

; text
FONT        = 0xB0000000                        ; zero terminated, 8x16 UTF-8
FONT_CP866  = 0x90000000                        ; zero terminated, 8x16 cp866
FONT_CHAR_W = 8
FONT_CHAR_H = 16

; colors
COLOR_ERROR = 0xAA0000
COLOR_OK    = 0x00AA00

; buttons
BTN_CLOSE   = 1
BTN_SAVE    = 2
BTN_SELECT  = 3
BTN_FLOPPY  = 4

; keys
KEY_ENTER   = 13
KEY_ESC     = 27

; results of a save beyond the file system errors, indexes of err_msgs
ERR_DEVICE  = 11
ERR_UNKNOWN = 12

FLOPPY_A    = 1                                 ; SF 16: the first drive
CLOSE_DELAY = 100                               ; 1/100 s

; proc_lib OpenDialog
OPENDIALOG_SAVE = 1
OPENDIALOG_OK   = 1
DIALOG_X    = 200
DIALOG_Y    = 120
DIALOG_W    = 420
DIALOG_H    = 320
NAME_MAX    = 256
PROCINFO_SIZE = 1024

; ====================================================================

struct BUTTON
        x               dd ?
        id              db ?
        caption         dd ?
ends

macro button_row x, id, caption
{
        local   start
start:
        dd      x
        db      id
        dd      caption
        assert  $ - start = sizeof.BUTTON
}

; a text and the number of its characters: its bytes but the ones that go
; on with a character, 10xxxxxx; CAPTION_MAX is the longest
CAPTION_MAX = 0

struc caption string
{
        local   n, b

        . db    string, 0

        n = 0
        repeat  $ - . - 1
                load    b byte from . + % - 1
                if b shr 6 <> 10b
                        n = n + 1
                end if
        end repeat
        .chars = n

        if n > CAPTION_MAX
                CAPTION_MAX = n
        end if
}

; ====================================================================

title           db "RDsave 2.0", 0

buttons:
        ;          x         id          caption
        button_row BTN_COL1, BTN_SAVE,   btn_save
        button_row BTN_COL2, BTN_SELECT, btn_select
        button_row BTN_COL3, BTN_FLOPPY, btn_floppy
buttons_end:

err_msgs:
        dd msg_ok, e1, e2, e3, e4, e5, e6, e7, e8, e9, e10, e11, e_unknown

key_autoclose   db "autoclose", 0
default_name    db "kolibri.img", 0

importLib:
library libini, "libini.obj", proclib, "proc_lib.obj"

import  libini, \
        ini_get_str, "ini_get_str", \
        ini_get_int, "ini_get_int", \
        ini_set_str, "ini_set_str"

import  proclib, \
        OpenDialog_Init, "OpenDialog_init", \
        OpenDialog_Start, "OpenDialog_start"

OpenDialog_data:
        .type           dd OPENDIALOG_SAVE
        .procinfo       dd procinfo
        .com_area_name  dd opendialog_area
        .com_area       dd 0
        .opendir_path   dd temp_dir_path
        .default_dir    dd opendialog_dir
        .start_path     dd opendialog_path
        .draw_window    dd draw_window
        .status         dd 0
        .openfile_path  dd dialog_path
        .filename_area  dd filename_area
        .filter_area    dd filter
        .x_size         dw DIALOG_W
        .x_start        dw DIALOG_X
        .y_size         dw DIALOG_H
        .y_start        dw DIALOG_Y

opendialog_area db "FFFFFFFF_open_dialog", 0
opendialog_path db "/sys/File Managers/opendial", 0
opendialog_dir  db "/", 0

filter:
        dd .end - filter
        db "IMG", 0
        db "IMA", 0
.end:
        db 0

; ====================================================================

if lang eq ru_RU

lab_target      caption "Сохранить в:"
btn_save        caption "Сохранить"
btn_select      caption "Выбрать файл..."
btn_floppy      caption "На дискету A"
tgt_boot        db "загрузочный носитель", 0
tgt_none        db "путь не выбран", 0
msg_saving      db "Сохранение образа...", 0
msg_ok          db "Образ сохранён успешно", 0
e1              db "не определена база и/или раздел жёсткого диска", 0
e2              db "функция не поддерживается данной файловой системой", 0
e3              db "неизвестная файловая система", 0
e4              db "зарезервировано (код 4)", 0
e5              db "неверный путь", 0
e6              db "файл закончился", 0
e7              db "указатель вне памяти приложения", 0
e8              db "диск переполнен", 0
e9              db "файловая структура разрушена", 0
e10             db "доступ запрещён", 0
e11             db "ошибка устройства", 0
e_unknown       db "неизвестная ошибка", 0

else if lang eq es_ES

lab_target      caption "Guardar en:"
btn_save        caption "Guardar"
btn_select      caption "Elegir archivo..."
btn_floppy      caption "Al disquete A"
tgt_boot        db "medio de arranque", 0
tgt_none        db "ruta no seleccionada", 0
msg_saving      db "Guardando la imagen...", 0
msg_ok          db "Imagen guardada con éxito", 0
e1              db "base y/o partición del disco duro no definida", 0
e2              db "el sistema de archivos no soporta esta función", 0
e3              db "sistema de archivos desconocido", 0
e4              db "reservado (código 4)", 0
e5              db "ruta incorrecta", 0
e6              db "fin de archivo", 0
e7              db "el puntero está fuera de la memoria de la aplicación", 0
e8              db "disco lleno", 0
e9              db "estructura de archivos dañada", 0
e10             db "acceso denegado", 0
e11             db "error de dispositivo", 0
e_unknown       db "error desconocido", 0

else

lab_target      caption "Save to:"
btn_save        caption "Save"
btn_select      caption "Select file..."
btn_floppy      caption "To floppy A"
tgt_boot        db "boot medium", 0
tgt_none        db "path not selected", 0
msg_saving      db "Saving the image...", 0
msg_ok          db "Image saved successfully", 0
e1              db "hard disk base and/or partition not defined", 0
e2              db "the file system does not support this function", 0
e3              db "unknown file system", 0
e4              db "reserved (code 4)", 0
e5              db "incorrect path", 0
e6              db "end of file", 0
e7              db "pointer is outside of application memory", 0
e8              db "disk is full", 0
e9              db "file structure is destroyed", 0
e10             db "access denied", 0
e11             db "device error", 0
e_unknown       db "unknown error", 0

end if

; a button fits the longest caption
BTN_W       = CAPTION_MAX*FONT_CHAR_W + 2*GAP

; ====================================================================

align 4
boot_src        rd 1
autoclose       rd 1
picked          rd 1
status_text     rd 1
status_color    rd 1

sc              system_colors

fname_buf       rb PATH_MAX
dialog_path     rb PATH_MAX
temp_dir_path   rb PATH_MAX
filename_area   rb NAME_MAX
procinfo        rb PROCINFO_SIZE
