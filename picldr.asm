; Copyright (C) 2004 GFRN systems
;
; This program is free software; you can redistribute it and/or
; modify it under the terms of the GNU General Public License as
; published by the Free Software Foundation; either version 2 of the
; License, or (at your option) any later version.
;
; This program is distributed in the hope that it will be useful, but
; WITHOUT ANY WARRANTY; without even the implied warranty of
; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
; See the GNU General Public License for more details.
;
; You should have received a copy of the GNU General Public License
; along with this program; if not, write to the Free Software
; Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA
; 02111-1307, USA.
;
; The latest version of this program may be found at
; http://openflash.sourceforge.net
;
; $Header: /home/skip/CVSROOT/picldr/picldr.asm,v 1.1 2004/05/01 16:55:19 Skip Exp $
; $Log: picldr.asm,v $
; Revision 1.1  2004/05/01 16:55:19  Skip
; Initial revision
;
;
;Simple Intel hex loader/programmer.
; 
;Programs a line at a time is into flash and then sends a single character
;response (following receipt of a carrage return).  Host software must wait 
;for the response before sending the next line.
;
;Loader is entered by holding the serial line in a space state while the
;PIC is turned on (or reset).  If the serial line is in a mark state 
;immediately after reset the normal application code is run.
;
;Modifications to application program to use loader:
;  1. Start startup at address 2 rather than zero.
;  2. Start application code after the end of loader.
;  3. Ensure only addresses below end of loader programmed by hex file
;     are 2 (start vector), 3 and 4 (interrupt vector)
;
;Response after receiving a carrage return character:
;'B' - Begin sending (first line, no prior status to report)
;'P' - Programmed data Ok
;'E' - program Error
;'C' - Checksum error
;'S' - Syntax error (non-hex digit received)
;'I' - last record type Ignored
;'F' - Finished ... jumping to application
;'R' - program address out of range (probably the configuration word), 
;      record ignored.

;Typical Intel Hex record:
;:10 00 00 00 00 29 00 00 00 00 00 00 A0 00 03 0E 83 01 C3 00 CF
;<byte count><load adr msb><load adr lsb><type><data>...<checksum>
;<type> 0: data record
;       1: end record
;       2: extended segment address record
;       3: start segment address record
;       4: extended linear address record
;       5: start linear address record
;
        IFDEF __16F873
        processor       16F873
        include <p16f873.inc>
#define MAX_FLASH_ADR   H'0fff'
        endif
        
        IFDEF __16F877A
        processor       16F877a
        include <p16f877a.inc>
#define MAX_FLASH_ADR   H'1fff'
#define SUFFIX_A_PART   1
        endif
        
        ERRORLEVEL -302 ;remove messages about using proper bank
        __config  _HS_OSC & _BODEN_ON & _CP_OFF & _PWRTE_ON & _WDT_OFF & _LVP_OFF

;#define         SIMULATE


        ifndef SIMULATE
;The following software timing loop constants assume a 20 Mhz clock
;adjust as needed for your actual clock.  Actual delay is not critical
;along as TIME_CONSTANT1, TIME_CONSTANT2 is long enough to ensure that
;the serial input is in it's true state.
;TIME_CONSTANT3, TIME_CONSTANT4 should delay longer than a character
;time at the serial line's baud rate.
        
#define         TIME_CONSTANT1  0x91
#define         TIME_CONSTANT2  3

#define         TIME_CONSTANT3  0x80
#define         TIME_CONSTANT4  2
        else
;dummy time constants to make use of the simulator less frustrating
#define         TIME_CONSTANT1  1
#define         TIME_CONSTANT2  1
#define         TIME_CONSTANT3  1
#define         TIME_CONSTANT4  1
        endif
        

loadhex         udata
datacount       res     1
progcount       res     1
response        res     1       ;
checksum        res     1       ;
rxdata          res     1       ;
datastart       res     1       ;
temp            res     1
padbytes        res     1       ;
                
;line of hex data loaded here
                res     2       ;pad boundary adjustment
hexcount        res     1
hex_adr_msb     res     1
hex_adr_lsb     res     1
rec_type        res     1
hex_data        res     16
delay           res     1               
delay1          res     1
delay2          res     1

        ifdef   SUFFIX_A_PART
SHARED  udata
chkdata         res     1       ;
chkdatah        res     1       ;
adr_msb         res     1
adr_lsb         res     1
        endif


STARTUP code
        goto    startup

PROG1   code

;get a character from the serial port
getch   btfss   PIR1,RCIF       ;
        ifndef SIMULATE
        goto    getch           ;
        else
        nop
        endif
        movf    RCREG,w         ;
        movwf   rxdata          ;save it 
        return

getnibble
        call    getch           ;get a character
        movlw   '0'             ;
        subwf   rxdata,f        ;
        btfss   STATUS,C        ;
        goto    badchar         ;
        movlw   0xa             ;> 9 ?
        subwf   rxdata,w        ;
        btfss   STATUS,C        ;
        goto    getnib1
        movlw   7               ;
        subwf   rxdata,f        ;adjust
        btfss   STATUS,C        ;
        goto    badchar         ;
getnib1
        movf    rxdata,w        ;        
        return
        
badchar movlw   'S'             ;syntax error, non hex digit received
        goto    setresponse     ;

gethex  call    getnibble       ;
        movwf   INDF            ;
        swapf   INDF,f          ;swap nibbles and save msb
        call    getnibble       ;
        iorwf   INDF,f          ;or in lsb
        movf    INDF,w          ;get byte 
        addwf   checksum,f      ;update checksum
        incf    FSR,f           ;
        return                  ;

startup
        ;initialize uart for 19,200, 8 data bits, no parity
        BSF     STATUS,RP0      ;Bank 1
        movlw   d'64'           ;19200 divider, 20 Mhz clock, BRGH = 1
        movwf   SPBRG
        
        BCF     STATUS,RP0      ;Bank 0
        movlw   0x90            ;Serial port enable, continuous receive
        movwf   RCSTA           ;
        
        BSF     STATUS,RP0      ;Bank 1
        movlw   0x24            ;TX enable, high speed async mode
        movwf   TXSTA           ;
        BCF     STATUS,RP0      ;Bank 0
        
        ;delay for about 100 milliseconds to give time for things to stabilize
        
        clrf    delay           ;
        movlw   TIME_CONSTANT1  ;
        movwf   delay1          ;
        movlw   TIME_CONSTANT2  ;
        movwf   delay2          ;
podelay decfsz  delay,f         ;
        goto    podelay         ;
        decfsz  delay1,f        ;
        goto    podelay         ;
        decfsz  delay2,f        ;
        goto    podelay         ;
        
        ;read the Rxd input to the UART to determine if we should run 
        ;the app or not.  If it's in a marking state (idle) jump into the
        ;application code, otherwise 
        
        btfsc   PORTC,7         ;UART input in a SPACE ?
        goto    2               ;(hopefully the app has programmed a jump here!)
        
        ;watch the RxD input pin for about 100 milliseconds, if it stays in
        ;a SPACE state for the entire 100 milliseconds then enter the loader,
        ;otherwise jump to the application

        clrf    delay           ;
        movlw   TIME_CONSTANT3  ;
        movwf   delay1          ;
        movlw   TIME_CONSTANT4  ;
        movwf   delay2          ;
podelay1
        btfsc   PORTC,7         ;UART input in a SPACE ?
        goto    2               ;(hopefully the app has programmed a jump here!)
        decfsz  delay,f         ;
        goto    podelay1        ;
        decfsz  delay1,f        ;
        goto    podelay1        ;
        decfsz  delay2,f        ;
        goto    podelay1        ;
        
        ;The RxD input has been in a space state for 100 milliseconds, start
        ;the loader
                   
        movlw   'B'             ;set first prompt character
        movwf   TXREG           ;and send it
        
setresponse
        movwf   response        ;
        ;intentional fall thru to hex0

hex0    call    getch           ;
        movlw   0xd             ;cr ?
        subwf   rxdata,w        ;
        btfss   STATUS,Z        ;
        goto    hex3            ;jump if not
        movf    response,w      ;get response character
        movwf   TXREG           ;send it
        movlw   'F'             ;finished ?
        subwf   response,w      ;
        btfsc   STATUS,Z        ;
        goto    2               ;(hopefully the app has programmed a jump here!)
        goto    hex0            ;keep waiting
        
hex3    movlw   ':'
        subwf   rxdata,w
        btfss   STATUS,Z        ;
        goto    hex0            ;not a ':'
        
        movlw   high hexcount
        movwf   PCLATH
        movlw   low hexcount
        movwf   FSR             ;
        clrf    checksum        ;

hex1    call    gethex          ;get line count
        movf    hexcount,w      ;
        movwf   progcount       ;save it
        bcf     STATUS,C        ;divide progcount by 2 to get word count
        rrf     progcount,f     ;
        movlw   4               ;+ 4 bytes to include load adr & checksum
        addwf   hexcount,f      ;

hex2:   call    gethex          ;get a byte
        decfsz  hexcount,f      ;
        goto    hex2            ;
        
        ;check the checksum
        movf    checksum,w      ;
        btfsc   STATUS,Z        ;
        goto    dotype          ;checksum good
        ;echo 'C' to indicate checksum error
        movlw   'C'             ;        
        goto    setresponse     ;
        
dotype  movf    rec_type,w      ;
        btfsc   STATUS,Z        ;
        goto    prgdata         ;type 0
        movlw   'F'             ;if it's a type 1 we're Finished!
        decf    rec_type,f      ;
        btfss   STATUS,Z        ;
        ;ignore any other type of record
        movlw   'I'             ;        
        goto    setresponse     ;

;copy data to flash
prgdata:
        movlw   'V'             ;assume nothing will need to be programmed
        movwf   response        ;
        
        ;copy load address from hex buffer
        movf    hex_adr_msb,w   ;
        movwf   adr_msb         ;
        movf    hex_adr_lsb,w   ;
        movwf   adr_lsb         ;
        
        movlw   low hex_data    ;
        movwf   datastart       ;

        bcf     STATUS,C        ;divide load address by 2 to get word address
        rrf     adr_msb,f       ;
        rrf     adr_lsb,f       ;

        ;check the address.
        movlw   (high MAX_FLASH_ADR) + 1
        subwf   adr_msb,w       ;
        btfsc   STATUS,C        ;
        goto    bad_adr         ;
        
        ifdef   SUFFIX_A_PART
        ;'A' parts must be programmed 4 bytes at a time starting
        ;on a 4 byte boundary.  Calculate the number of extra bytes we 
        ;need to 'program' at the beginning of the block to get to an 
        ;4 byte boundary
        
        movlw   3               ;
        andwf   adr_lsb,w       ;
        btfsc   STATUS,Z        ;
        goto    nobegpad        ;

        clrf    datacount       ;        
begpad  incf    progcount,f     ;
        decf    datastart,f     ;
        decf    datastart,f     ;
        incf    datacount,f     ;
        decf    adr_lsb,f       ;
        
        movlw   3               ;
        andwf   adr_lsb,w       ;
        btfss   STATUS,Z        ;
        goto    begpad          ;
        
;read padding bytes at beginning of block
        BSF     STATUS,RP1      ;Bank 2
        movf    adr_msb,w       ;Flash address MSB
        MOVWF   EEADRH          ;
        movf    adr_lsb,w       ;Flash address LSB
        MOVWF   EEADR           ;
        BCF     STATUS,RP1      ;Bank 0
        movf    datastart,w     ;get starting address of data in RAM
        movwf   FSR             ;
        call    rd_data         ;

nobegpad
        ;calculate now many pad bytes we need to add to the end of data
        movf    progcount,w     ;
        movwf   temp            ;
        call    calcpad         ;
        movf    padbytes,w      ;
        btfsc   STATUS,Z        ;
        goto    noendpad        ;
        movwf   datacount       ;
        
        BSF     STATUS,RP1      ;Bank 2
        movf    adr_msb,w       ;Flash address MSB
        MOVWF   EEADRH          ;
        movf    adr_lsb,w       ;Flash address LSB
        BCF     STATUS,RP1      ;Bank 0
        addwf   progcount,w     ;
        BSF     STATUS,RP1      ;Bank 2
        btfsc   STATUS,Z        ;
        incf    EEADRH,f        ;carry into MSB
        MOVWF   EEADR           ;
        BCF     STATUS,RP1      ;Bank 0
        movf    datastart,w     ;get starting address of data in RAM
        addwf   progcount,w     ;plus program count * 2
        addwf   progcount,w     ;
        movwf   FSR             ;save end addr in RAM
        call    rd_data         ;read the end padding bytes
        movf    padbytes,w      ;
        addwf   progcount,f     ;adjust program count for extra padding bytes
        
noendpad        
        endif   ;SUFFIX_A_PART
        
        call    chk_data        ;any need to program it ?
        btfsc   STATUS,Z        ;
        goto    hex0            ;nope !
        
        movlw   'P'             ;we're going to program at least one word
        movwf   response        ;
        call    setupadr
prg_loop
        movf    INDF,w          ;
        movwf   chkdata         ;save lsb
        incf    FSR,f           ;
        movf    INDF,w          ;
        movwf   chkdatah        ;save msb of data
        incf    FSR,f           ;
        
        ;load data into EEDATAH, EEDATA
        BSF     STATUS,RP1      ;Bank 2
        movf    chkdatah,w      ;get msb of data
        MOVWF   EEDATH          ;msb of data
        movf    chkdata,w       ;get lsb of data
        MOVWF   EEDATA          ;lsb of data

        ;program it        
        BSF     STATUS,RP0      ;Bank 3
        BSF     EECON1,WREN     ;Enable writes
        MOVLW   0x55            ;Write 55h to
        MOVWF   EECON2          ;EECON2
        MOVLW   0xAA            ;Write AAh to
        MOVWF   EECON2          ;EECON2
        
        BSF     EECON1,WR       ;Start write operation
        NOP                     ;Two NOPs to allow micro
        NOP                     ;to setup for write
        
        BCF     EECON1,WREN     ;Disable writes
        
        BCF     STATUS,RP0      ;Bank 2
        incf    EEADR,f         ;
        btfsc   STATUS,Z        ;
        incf    EEADRH,f        ;carry into MSB
        BCF     STATUS,RP1      ;Bank 0
        decfsz  datacount,f     ;
        goto    prg_loop        ;

        ;verify it
verify  call    chk_data        ;program ok ?
        btfsc   STATUS,Z        ;
        goto    hex0            ;we're really done now.

prg_error
        movlw   'E'             ;
        goto    setresponse     ;

        ;Hex files generated by MPLAB include addresses outside of the
        ;flash range for things such as the configuration word.  This is
        ;not an error, but we can't program them and addresses above the
        ;maximum flash address wrap and clobber other addresses.
bad_adr
        movlw   'R'             ;
        goto    setresponse     ;

sendchar
        bsf     STATUS,RP0      ;bank 1
sendwait
        btfss   TXSTA,TRMT      ;
        goto    sendwait        ;
        bcf     STATUS,RP0      ;bank 0
        movwf   TXREG           ;
        return                  ;

setupadr
        movf    progcount,w     ;setup loop count
        movwf   datacount       ;

        movf    datastart,w     ;get starting address of data in RAM
        movwf   FSR             ;
        
        BSF     STATUS,RP1      ;Bank 2
        movf    adr_msb,w       ;Flash address MSB
        MOVWF   EEADRH          ;
        movf    adr_lsb,w       ;Flash address LSB
        MOVWF   EEADR           ;

        BCF     STATUS,RP1      ;Bank 0
        return
        
;compare data in flash @ adr_msb, adr_lsb, against RAM at datastart
;for datacount bytes
chk_data
        call    setupadr
chk_loop
        BSF     STATUS,RP0      ;Bank 3
        BSF     STATUS,RP1      ;
        BSF     EECON1,EEPGD    ;Point to Program memory
        bsf     EECON1,RD       ;read flash
        nop
        nop
        BCF     STATUS,RP0      ;Bank 2
        movf    EEDATA,w        ;get LSB of data
        BCF     STATUS,RP1      ;Bank 0
        subwf   INDF,w          ;
        btfss   STATUS,Z        ;
        return                  ;Z flag tells all
        
        incf    FSR,f           ;
        BSF     STATUS,RP1      ;Bank 2
        incf    EEADR,f         ;increment flash ADR
        btfsc   STATUS,Z        ;
        incf    EEADRH,f        ;carry into MSB
        movf    EEDATH,w        ;get MSB of data
        BCF     STATUS,RP1      ;Bank 0
        subwf   INDF,w          ;
        btfss   STATUS,Z        ;
        return                  ;Z flag tells all
        
        incf    FSR,f           ;
        decfsz  datacount,f     ;
        goto    chk_loop        ;
        bsf     STATUS,Z        ;
        return                  ;Z flag tells all        

;read data from flash into ram for datacount bytes
rd_data
        BSF     STATUS,RP0      ;Bank 3
        BSF     STATUS,RP1      ;
        BSF     EECON1,EEPGD    ;Point to Program memory
        bsf     EECON1,RD       ;read flash
        nop
        nop
        BCF     STATUS,RP0      ;Bank 2
        movf    EEDATA,w        ;get LSB of data
        BCF     STATUS,RP1      ;Bank 0
        movwf   INDF            ;
        incf    FSR,f           ;
        BSF     STATUS,RP1      ;Bank 2
        incf    EEADR,f         ;increment flash ADR
        btfsc   STATUS,Z        ;
        incf    EEADRH,f        ;carry into MSB
        movf    EEDATH,w        ;get MSB of data
        BCF     STATUS,RP1      ;Bank 0
        movwf   INDF            ;
        incf    FSR,f           ;
        decfsz  datacount,f     ;
        goto    rd_data         ;
        return                  ;

;calculate number of bytes to add to temp make temp a multiple of 4
;return result in padbytes
calcpad
        clrf    padbytes        ;
padloop
        movlw   3               ;
        andwf   temp,w          ;
        btfsc   STATUS,Z        ;
        return                  ;
        incf    padbytes,f      ;
        incf    temp,f          ;
        goto    padloop         ;
        
        end
        
