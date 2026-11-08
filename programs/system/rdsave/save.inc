; The save rule of RDsave and End: the boot medium, then the [RDSave] path
; of app.ini

PATH_MAX         = 4096
RD_ERR_NO_MEDIUM = 2                            ; SF 18.6: unknown or read-only

; fname_buf <- the path from the ini, empty if there is none
rd_read_path:
        invoke  ini_get_str, ini_file, ini_sec, key_path, fname_buf, PATH_MAX, ini_no_path
        ret

; fname_buf = the path from the ini or empty: eax = 0 or a file system error
rd_save:
        mcall   SF_SYSTEM, SSF_RD_TO_HDD, 0
        cmp     eax, RD_ERR_NO_MEDIUM
        jne     .done

        cmp     byte [fname_buf], 0
        je      .done

        mcall   SF_SYSTEM, SSF_RD_TO_HDD, fname_buf

.done:
        ret

ini_file        db "/sys/settings/app.ini", 0
ini_sec         db "RDSave", 0
key_path        db "path", 0
ini_no_path     db 0
