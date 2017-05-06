      list p=16f877                 ; list directive to define processor
      #include <p16f877.inc>        ; processor specific variable definitions
      
    
      __CONFIG _CP_OFF & _WDT_OFF & _BODEN_ON & _PWRTE_ON & _HS_OSC & _WRT_ENABLE_ON & _CPD_OFF & _LVP_OFF
    #include <rtc_macros.inc>

    cblock  0x20
        COUNTH
        COUNTM  
        COUNTL  
        Table_Counter
        lcd_tmp 
        lcd_d1
        lcd_d2
        com 
        dat ; was in sample code
        count   ; used to convert optime to decimal for display
        ones    ; ones digit of the converted binary number
        tens    ; tens digit of the converted binary number
        huns    ; hundreds digit of the converted binary number (hopefully not used)
        binary_num ; move optime to this variable to allow binary --> decimal for display
        w_temp  ; saves the value in the working register
        status_temp ; saves the current state of the status register (for ISR)
        barrel1:4
        barrel2:4 ;41
        barrel3:4 ;44
        barrel4:4 ;47
        barrel5:4 ;50
        barrel6:4 ;53
        barrel7:4 ;56
        ;1: Stores Tall/Short Barrel, Stores E/HF/F
        ;2: Location (stores distance < 256 cm)
        ;3: Location (if distance > 256 cm)
        barrelnum   ;current barrel number
        barreltemp
        option_temp
        Delay1
        Delay2
        TIMCNT
        voltage_IR
        counter_IR
        lastop_IR ;checks last operation of IR
        IR_DETECT
        Time_High
        Time_Low
        ad_store
        dis_counter ;increments to 17 for the encoder
        dis_counter4 ;increments to 4 before incrementing 17 times for the encoder
        min:2   ;temporary registers for operation time
        sec:2
        initmin:2
        initsec:2
        finalmin:2
        finalsec:2  
        armextend ;set to 1 when arm extended
        Dis_Ones
        Dis_Tens
        Dis_Hunds
        Dis_Thous
        ultra_time
        threshold_time
        barrel_data
    endc    
    
    cblock  0x70
    
    COUNTH1 ;const used in delay
    COUNTM1 ;const used in delay
    COUNTL1 ;const used in delay
    
    endc
    

    ;Declare constants for pin assignments (LCD on PORTD)
        #define RS  PORTD,2
        #define E   PORTD,3
        
        ;ANALOG PINS
        #define IR1 PORTA,0
        #define IR2 PORTA,1
        #define IR3 PORTA,2
        #define IR4 PORTA,3
        #define IR5 PORTA,5
        #define IR6 PORTE,0
        #define IR7 PORTE,1
        #define IR8 PORTE,2
        
        ;DIGITAL PINS
        #define DCA1    PORTC,1 ;DC motor A1 PWM 
        #define DCA2    PORTC,0 ;DC motor A2
        #define DCB1    PORTC,2 ;DC motor B1 PWM
        #define DCB2    PORTD,5 ;DC motor B2 ;A7
        #define DCC1    PORTD,6 ;DC motor C1
        #define DCC2    PORTD,4 ;DC motor C2
        
        #define US_TRIG PORTC,5 ;Ultrasonic TRIGGER
        #define US_ECHO PORTC,6 ;Ultrasonic ECHO
        
        #define LS  PORTC,7 ;Laser Sensor Bottom - Digital 
        ;#define    LSH PORTD,1 ;Laser Sensor Top - Digital 
        #define ES  PORTD,0 ;encoder sensor
         ORG       0x0000     ;RESET vector must always be at 0x00
         goto      init       ;Just jump to the main code section.
         
;DCB???
    
;***************************************
; Delay: ~160us macro
;***************************************
LCD_DELAY macro
    movlw   0xFF
    movwf   lcd_d1
    decfsz  lcd_d1,f
    goto    $-1
    endm


;***************************************
; Display macro
;***************************************
Display macro   Message
        local   loop_
        local   end_
        clrf    Table_Counter
        clrw        
loop_   movf    Table_Counter,W
        call    Message
        xorlw   B'00000000' ;check WORK reg to see if 0 is returned
        btfsc   STATUS,Z
            goto    end_
        call    WR_DATA
        incf    Table_Counter,F
        goto    loop_
end_
        endm

bank0   macro
    bcf STATUS, RP0
    bcf STATUS, RP1
    endm
bank1   macro
    bcf STATUS, RP0
    bsf STATUS, RP1
    endm
bank2   macro
    bsf STATUS, RP0
    bcf STATUS, RP1
    endm
bank3   macro
    bsf STATUS, RP0
    bcf STATUS, RP1
    endm
binconv macro
    movwf   binary_num
    call    BIN2BCD
    movf    huns,W
    call    WR_DATA
    movf    tens,W
    call    WR_DATA
    movf    ones,W
    call    WR_DATA
    endm
    
    
;***************************************
; Initialize LCD
;***************************************
init
         clrf      INTCON         ; No interrupts
     
;   bsf       INTCON, GIE   ; enable global interrupts
;   bsf       INTCON, 5     ; enable timer 0 interrupts
;   bcf       INTCON, 4     ; clear timer0 interrupt flag
;   bcf       INTCON, 2     ; disable internal interrupts (from Port B)
;   bcf       INTCON, 1     ; clear internal interrupt flag.
     
     ; NEED TO FIX THESE SETTINGS
        bsf       STATUS,RP0     ; select bank 1
    movlw     b'00101111'    ; set RA4 as output
        movlw     b'11111011'    ; Set required keypad inputs
        movwf     TRISB
        clrf      TRISC          ; All port C is output
              ;Set SDA and SCL to high-Z first as required for I2C
    bsf   TRISC,4         
    bsf   TRISC,3
    bsf   TRISC,7
    bsf   TRISC,6   ;US_ECHO
        clrf      TRISD          
    bsf   TRISD,0 ;the encoder is an input
    bsf   TRISD,1
    
    movlw     b'00000111'    ;set RE0-3 as input for IR sensors
    movwf     TRISE
    
        bcf       STATUS,RP0     ; select bank 0
        clrf      PORTA
        clrf      PORTB
        clrf      PORTC
        clrf      PORTD
        clrf      PORTE 
        

    ;Set up I2C for communication
    call    i2c_common_setup
    ;rtc_resetAll
         
    ;Used to set up time in RTC, load to the PIC when RTC is used for the first time
    call      set_rtc_time
          
    call      InitLCD     ;Initialize the LCD (code in lcd.asm; imported by lcd.inc)
     
     
; Set up Pulse Width Modulation (PWM)
    bsf         STATUS,RP0          ; Bank1
    movlw       b'11111001'         ; Configure PR2 with 10 kHz
    movwf       PR2
    bcf         STATUS,RP0          ; Bank0
    movlw       b'00001111'         ; Configure RC1 and RC2 as PWM outputs 
    movwf       CCP2CON             ; RC1
    movwf       CCP1CON
    movlw       b'00000100'         ; Configure Timer2
    movwf       T2CON               ; Set to prescaler 1:1, postscaler 1:1 , enabled
    movwf       T1CON

    ; Initialize motor variable
    clrf        CCPR2L              ; Set RC1 to 0% duty cycle
    clrf        CCPR1L
    ;bcf        PORTB,0
    ;bcf        PORTC,0
    ;bcf        PORTC,2
    ;bsf        PORTC,5
    ;bcf        PORTC,6  
    
    
    
;***************************************
; Main code
;***************************************

        
Main    


        btfss   PORTB, 1
        goto    $-1
     
        Display Welcome_Msg1
        
        btfsc   PORTB, 1    ;check if cleared 
        goto    $-1
        
        btfss   PORTB, 1
        goto    $-1
         
        call    Switch_Lines

        Display Welcome_Msg2
        
test        
        btfss   PORTB, 1    ;check for input from KEYPAD
        goto    $-1     ;if NOT, keep polling
        
        swapf   PORTB, W    ;when input is detected, swamp nibbles  
                    ;PORTB <7-4> moved to <3-0> in w
        andlw   0x0F        
        xorlw   b'00001100' ;checks if 12th key is pressed *
        btfss   STATUS, Z   ;if pressed, then Z=1
        goto    test        ;if NOT, then keep checking until * is pressed
        
        btfsc   PORTB, 1    ;keep iterating until key is released
        goto $-1
        goto START

        
;***************************************
; Look up table
;***************************************



Welcome_Msg1    
        addwf   PCL,F
        dt      "Welcome!", 0
Welcome_Msg2    
        addwf   PCL,F
        dt      "Press * to Start", 0
Message1
        addwf   PCL,F
        dt      "T", 0
Message2    
        addwf   PCL,F
        dt      " B:", 0
Message3    
        addwf   PCL,F
        dt      "Press * to Reset", 0
Message4
        addwf   PCL,F
        dt      "Press # for Info", 0
Message5    
        addwf   PCL,F
        dt      " TP:", 0
Message6
        addwf   PCL,F
        dt      "L:", 0
Message7
        addwf   PCL,F
        dt      "D:", 0
Message8    
        addwf   PCL,F
        dt      " OT", 0

;***************************************
; OPERATION CODE
;***************************************   

        
START       
        call Clear_Display


        ;initializing
        
        ;intialize barrel1/2/3/4/5/6/7
        movlw   b'01011000' ;ASCII X
        movwf   barrel1
        movwf   barrel2
        movwf   barrel3
        movwf   barrel4
        movwf   barrel5
        movwf   barrel6
        movwf   barrel7
        
        ;intialize barrel1/2/3/4/5/6/7 + 1
        
        movlw   b'00100011' ;#
        movwf   barrel1+1  
        movwf   barrel2+1       
        movwf   barrel3+1
        movwf   barrel4+1
        movwf   barrel5+1
        movwf   barrel6+1
        movwf   barrel7+1
        movwf   barrel1+2   
        movwf   barrel2+2           
        movwf   barrel3+2
        movwf   barrel4+2
        movwf   barrel5+2   
        movwf   barrel6+2
        movwf   barrel7+2
        movwf   barrel1+3   
        movwf   barrel2+3   
        movwf   barrel3+3
        movwf   barrel4+3
        movwf   barrel5+3
        movwf   barrel6+3
        movwf   barrel7+3
        
        movlw   d'0'
            movwf   barrelnum
        movwf   barreltemp
        
        
        movlw   b'00110000'
        movwf   Dis_Ones
        movlw   b'00110000'
        movwf   Dis_Tens
        movlw   b'00110000'
        movwf   Dis_Hunds
        movlw   b'00110000'
        movwf   Dis_Thous
        

        movlw   d'0'
        movwf   IR_DETECT
        movwf   threshold_time
        bsf STATUS, C ;preset C to 1
        movlw   b'0'
        movwf   Time_High
        movlw   b'0'
        movwf   Time_Low
        movwf   dis_counter
        movwf   dis_counter4        

        

;check if ALl the IRs work
;TEST_IR
;       call    CHECK_IR1
;       movfw   IR_DETECT
;       call    CHECK_DETECT
;       
;       call    CHECK_IR2
;       movfw   IR_DETECT
;       call    CHECK_DETECT
;       
;       call    CHECK_IR3
;       movfw   IR_DETECT
;       call    CHECK_DETECT
;       
;       call    CHECK_IR4
;       movfw   IR_DETECT
;       call    CHECK_DETECT
;       
;       call    Clear_Display
;       goto    TEST_IR
;       
;       
;CHECK_DETECT
;       xorlw   b'1'
;       btfss   STATUS,Z
;       goto    SHOWLOW
;       call    SHOWHIGH
;CHECK_EXIT     
;       return
;       
;SHOWHIGH
;       movlw   '1'
;       call    WR_DATA
;       return
;
;       
;SHOWLOW
;       movlw   '0'
;       call    WR_DATA
;       goto    CHECK_EXIT
;       
OPERATION_ENCODER
        movlw   b'0' ;reset the counter
        movwf   dis_counter
        ;call   Clear_Display
        btfss   ES ;check if ES gets a HIGH
        goto    OPERATION_ENCODER
        ;call   DISTANCECALL17
        
        ;check if 4 divisions are counted
        incf    dis_counter4
        movfw   dis_counter4
        xorlw   d'4'
        btfss   STATUS, Z ;Z=1 when dis_counter4=4
        goto    OPERATION_ENCODER
        call    DISTANCECALL17
        goto    OPERATION_ENCODER


    DISTANCECALL17
            movlw   b'0'
            movwf   dis_counter4
            movfw   dis_counter
            xorlw   d'17' ;Z=1 if dis_counter=17
            btfsc   STATUS,Z
            return ;if Z=1, return
            call    Distance_Count
            incf    dis_counter
            goto    DISTANCECALL17
;       
OPERATION_START
        
        
        
        ;call   Realtime 
        

        ;call   CHECK_DISTANCE
        ;btfsc  STATUS, C   ;if not set, then continue
        ;goto   END_OPERATION   ;if set, then turn back
        
        ;btfss  ES  ;check if Encoder Sensor detects
        ;goto   START1; if doesn't detect, continue
        ;call   Distance_Count  ;if so, increment the Distance      
        
        

START1      
        ;DISTANCE DISPLAY FOR DEBUGGING ONLY
        
        ;movlw  " " 
        ;call   WR_DATA
        ;movfw  Dis_Hunds
        ;call   WR_DATA
        ;movfw  Dis_Tens
        ;call   WR_DATA
        ;movfw  Dis_Ones
        ;call   WR_DATA
        ;call   Clear_Display
        
        ;DISTANCE DISPLAY FOR DEBUGGING ONLY
        
        ;movfw  armextend
        ;xorlw  b'0'
        ;btfss  STATUS,Z
        ;goto   RETRACT_ARM_BACK ;else, retract arm
        
    
        
        ;at this point, it is clear we have no obstructions, turn on the motors
        ;turn on the left motor, turn on the right motor
        call    MOTOR_ON_RC1
        call    MOTOR_ON_RC2
        
        
        ;*************TEST*
        ;call   RETRACT_ARM_BACK ;just to see the arm rotate back and forth with delay of 1 second
        ;*************TEST*
        
        ;we continue to operate until any of the 8 IR sensors detects something and
        ;at the same time, we are detecting if there is a column w/ the ultrasonic sesnor
        ;this is effectively a VERY FAST poll that checks between the IR sensors and the ultrasonic sensors
CHECK_IRSENSORS 

        ;checks all 8 IR sensors
        
        call    CHECK_IR1
        movfw   IR_DETECT
        call    CHECK_DETECT
        
        call    CHECK_IR2
        movfw   IR_DETECT
        call    CHECK_DETECT
    
        call    CHECK_IR3
        movfw   IR_DETECT
        call    CHECK_DETECT
        
        call    CHECK_IR4
        movfw   IR_DETECT
        call    CHECK_DETECT
        
        call    CHECK_IR5
        movfw   IR_DETECT
        call    CHECK_DETECT
        
        call    CHECK_IR6
        movfw   IR_DETECT
        call    CHECK_DETECT
        
        call    CHECK_IR7
        movfw   IR_DETECT
        call    CHECK_DETECT
        
        call    CHECK_IR8
        movfw   IR_DETECT
        call    CHECK_DETECT
        
        ;if none sensors detected, check US sensor
        goto    CHECK_US
        
        
CHECK_DETECT
        xorlw   b'1'
        btfss   STATUS,Z ;Z=1 if IR_DETECT = 1
        return ; if Z=0, return and check the next sensor
        goto    DETECTED ;if detected, check US
        
        
;;PURPOSE: Checks the ultrasonic, if detects it, it will stop the motors, rotate the arm
;;      ;and them come back and turn the motors back on so that it can 
;;      ;continue to check for barrels again
;;      ;if does not detect, then it will jump to keeping the motors on and 
;;      ;continue to check for barrels again
CHECK_US        
        call    ULTRASONIC
        ;C is set when Time_High > 3
        movlw   b'11' ;3
        subwf   Time_High,W
        btfss   STATUS, C
        call    RETRACT_ARM_BACK ;this means C<3, retract arm
        call    MOTOR_ON_RC1
        call    MOTOR_ON_RC2
        goto    CHECK_IRSENSORS   ;this means C>3, go back to checking
        
DETECTED    
        ;at this point, the LSL has been detected, so stop the motors
    
        call    MOTOR_BOTH_OFF
        ;now check if the LSH detects anything, if it does, it means it is a
        ;large barrel, if not, then it is a small barrel
        
        btfss   LS; if the laser detects AND the IR sensors detect, it is a large barrel
        goto    SHORTBARREL ;it is a short barrel
        goto    TALLBARRELL ;it is a large barel

        ;at this point, done recording and continue with operation
    
        goto OPERATION_START    


END_OPERATION
        ;turn back 
        call    RETRACT_ARM

        ;reset the distance
        movlw   b'00110000'
        movwf   Dis_Ones
        movlw   b'00110000'
        movwf   Dis_Tens
        movlw   b'00110000'
        movwf   Dis_Hunds
        
END_LOOP    ;add in to retrieve final operation time
        bsf DCA ;turn on motos to travel back
        bsf DCB
        call    CHECK_DISTANCE
        btfss   STATUS, C   ;if set, then end   
        goto    END_LOOP ;if not, keep going
        
        bcf DCA ;turn off DC motors
        bcf DCB
        goto    END_DISPLAY ;exit

    
END_DISPLAY 
        call    Clear_Display
        Display Message3
        call    Switch_Lines
        Display Message4
        
CHECK_PRESS1        
        btfss   PORTB, 1    ;check for input from KEYPAD
        goto    $-1     ;if NOT, keep polling
        swapf   PORTB, W    ;When input is detected, read it in to W
        andlw   0x0F
        goto    OPTION1 

OPTION1     ;checks if * was pressed
        movwf   option_temp
        xorlw   b'00001100'         ; Check to see if 12th key
        btfss   STATUS,Z            ; If status Z goes to 0, it is the 13th key, skip
        goto    OPTION2         ; If not check if it's B
        call    Clear_Display
        goto    Main              ; If it is, restart 
        
OPTION2     ;checks if # was pressed
        movf    option_temp, W
        xorlw   b'00001110'
        btfss   STATUS,Z
        goto    CHECK_PRESS1 ;resume polling
        call    Clear_Display
        btfsc   PORTB, 1    ;keep iterating until key is released
        goto $-1
        goto    POLL1

POLL1
        btfss   PORTB, 1    ;check for input from KEYPAD
        goto    Polltime1   ;if no input, poll INFO
        swapf   PORTB, W    ;when input is detected, read it in to W
        andlw   0x0F
        btfsc   PORTB, 1    ;keep iterating until key is released
        goto $-1
        goto    CHECKPRESS1 ;check which key was pressed
Polltime1   
        movlw   "T"     ;displays T for Real Time
        call    WR_DATA
        call    Realtime    ;displays Real Time
        Display Message2    ;displays B:    
        movlw   "1"     ;displays barrel #      
        call    WR_DATA     
        Display Message5 
        movfw   barrel1 ;T/S/E/HF/F
        call    Check_Type
        call    Switch_Lines
        Display Message6
        movfw   barrel1
        call    Check_Height
        Display Message7
        movfw   barrel1+3 ;ten digit first, how is this stored? Leave as O's for now
        call    WR_DATA
        movfw   barrel1+2
        call    WR_DATA
        movfw   barrel1+1
        call    WR_DATA
        Display Message8
        call    HalfS
        call    Clear_Display
        goto    POLL1
        

CHECKPRESS1
BACKWARD1   ;checks if 1 was pressed
        movwf   option_temp
        xorlw   b'00000000'         ;checks to see if "1" was pressed
        btfss   STATUS,Z            ;if status Z goes to 0, it is not "1"
        goto    FORWARD1         ;if not, check to see if "2" was pressed
        call    Clear_Display   
        goto    POLL7
FORWARD1    ;checks if 2 was pressed
        movf    option_temp, W
        xorlw   b'00000001'
        btfss   STATUS,Z
        goto    POLL1 ;resume polling
        call    Clear_Display
        goto    POLL2
;***************************************
; BARREL2
;***************************************
POLL2
        btfss   PORTB, 1    ;check for input from KEYPAD
        ;goto   $-1     ;if NOT, keep polling
        goto    Polltime2   
        swapf   PORTB, W    ;When input is detected, read it in to W
        andlw   0x0F
        btfsc   PORTB, 1    ;keep iterating until key is released
        goto $-1
        goto    CHECKPRESS2 

Polltime2   
        movlw   "T"     ;displays T for Real Time
        call    WR_DATA
        call    Realtime    ;displays Real Time
        Display Message2    ;displays B:    
        movlw   "2"     ;displays barrel #      
        call    WR_DATA     
        Display Message5
        movfw   barrel2 ;T/S/E/HF/F
        call    Check_Type
        call    Switch_Lines
        Display Message6
        movfw   barrel2
        call    Check_Height
        Display Message7
        movfw   barrel2+3 ;ten digit first, how is this stored? Leave as O's for now
        call    WR_DATA
        movfw   barrel2+2
        call    WR_DATA
        movfw   barrel2+1
        call    WR_DATA
        Display Message8
        call    HalfS
        call    Clear_Display
        goto    POLL2       
        
CHECKPRESS2
BACKWARD2   ;checks if 1 was pressed
        movwf   option_temp
        xorlw   b'00000000'         ;checks to see if "1" was pressed
        btfss   STATUS,Z            ;if status Z goes to 0, it is not "1"
        goto    FORWARD2         ;if not, check to see if "2" was pressed
        call    Clear_Display   
        goto    POLL1
FORWARD2    ;checks if 2 was pressed
        movf    option_temp, W
        xorlw   b'00000001'
        btfss   STATUS,Z
        goto    POLL2 ;resume polling
        call    Clear_Display
        goto    POLL3       

;***************************************
; BARREL3
;***************************************

POLL3
        btfss   PORTB, 1    ;check for input from KEYPAD
        ;goto   $-1     ;if NOT, keep polling
        goto    Polltime3
        swapf   PORTB, W    ;When input is detected, read it in to W
        andlw   0x0F
        btfsc   PORTB, 1    ;keep iterating until key is released
        goto $-1
        goto    CHECKPRESS3 

Polltime3   
        movlw   "T"     ;displays T for Real Time
        call    WR_DATA
        call    Realtime    ;displays Real Time
        Display Message2    ;displays B:    
        movlw   "3"     ;displays barrel #      
        call    WR_DATA     
        Display Message5 
        movfw   barrel3 ;T/S/E/HF/F
        call    Check_Type
        call    Switch_Lines
        Display Message6
        movfw   barrel3
        call    Check_Height
        Display Message7
        movfw   barrel3+3 ;ten digit first, how is this stored? Leave as O's for now
        call    WR_DATA
        movfw   barrel3+2
        call    WR_DATA
        movfw   barrel3+1
        call    WR_DATA
        Display Message8
        call    HalfS
        call    Clear_Display
        goto    POLL3
CHECKPRESS3
BACKWARD3   ;checks if 1 was pressed
        movwf   option_temp
        xorlw   b'00000000'         ;checks to see if "1" was pressed
        btfss   STATUS,Z            ;if status Z goes to 0, it is not "1"
        goto    FORWARD3         ;if not, check to see if "2" was pressed
        call    Clear_Display   
        goto    POLL2
FORWARD3    ;checks if 2 was pressed
        movf    option_temp, W
        xorlw   b'00000001'
        btfss   STATUS,Z
        goto    POLL2 ;resume polling
        call    Clear_Display
        goto    POLL4
        
;***************************************
; BARREL4
;***************************************

POLL4
        btfss   PORTB, 1    ;check for input from KEYPAD
        ;goto   $-1     ;if NOT, keep polling
        goto    Polltime4
        swapf   PORTB, W    ;When input is detected, read it in to W
        andlw   0x0F
        btfsc   PORTB, 1    ;keep iterating until key is released
        goto $-1
        goto    CHECKPRESS4 
Polltime4   
        movlw   "T"     ;displays T for Real Time
        call    WR_DATA
        call    Realtime    ;displays Real Time
        Display Message2    ;displays B:    
        movlw   "4"     ;displays barrel #      
        call    WR_DATA     
        Display Message5 
        movfw   barrel4 ;T/S/E/HF/F
        call    Check_Type
        call    Switch_Lines
        Display Message6
        movfw   barrel4
        call    Check_Height
        Display Message7
        movfw   barrel4+3 ;ten digit first, how is this stored? Leave as O's for now
        call    WR_DATA
        movfw   barrel4+2
        call    WR_DATA
        movfw   barrel4+1
        call    WR_DATA
        Display Message8
        call    HalfS
        call    Clear_Display
        goto    POLL4       
CHECKPRESS4
BACKWARD4   ;checks if 1 was pressed
        movwf   option_temp
        xorlw   b'00000000'         ;checks to see if "1" was pressed
        btfss   STATUS,Z            ;if status Z goes to 0, it is not "1"
        goto    FORWARD4         ;if not, check to see if "2" was pressed
        call    Clear_Display   
        goto    POLL3
FORWARD4    ;checks if 2 was pressed
        movf    option_temp, W
        xorlw   b'00000001'
        btfss   STATUS,Z
        goto    POLL4 ;resume polling
        call    Clear_Display
        goto    POLL5       
        
;***************************************
; BARREL5
;***************************************

POLL5
        btfss   PORTB, 1    ;check for input from KEYPAD
        ;goto   $-1     ;if NOT, keep polling
        goto    Polltime5
        swapf   PORTB, W    ;When input is detected, read it in to W
        andlw   0x0F
        btfsc   PORTB, 1    ;keep iterating until key is released
        goto $-1
        goto    CHECKPRESS5 

Polltime5   
        movlw   "T"     ;displays T for Real Time
        call    WR_DATA
        call    Realtime    ;displays Real Time
        Display Message2    ;displays B:    
        movlw   "5"     ;displays barrel #      
        call    WR_DATA     
        Display Message5 
        movfw   barrel5 ;T/S/E/HF/F
        call    Check_Type
        call    Switch_Lines
        Display Message6
        movfw   barrel5
        call    Check_Height
        Display Message7
        movfw   barrel5+3 ;ten digit first, how is this stored? Leave as O's for now
        call    WR_DATA
        movfw   barrel5+2
        call    WR_DATA
        movfw   barrel5+1
        call    WR_DATA
        Display Message8
        call    HalfS
        call    Clear_Display
        goto    POLL5
        
CHECKPRESS5
BACKWARD5   ;checks if 1 was pressed
        movwf   option_temp
        xorlw   b'00000000'         ;checks to see if "1" was pressed
        btfss   STATUS,Z            ;if status Z goes to 0, it is not "1"
        goto    FORWARD5         ;if not, check to see if "2" was pressed
        call    Clear_Display   
        goto    POLL4
FORWARD5    ;checks if 2 was pressed
        movf    option_temp, W
        xorlw   b'00000001'
        btfss   STATUS,Z
        goto    POLL5 ;resume polling
        call    Clear_Display
        goto    POLL6       
        
        
;***************************************
; BARREL6
;***************************************

POLL6
        btfss   PORTB, 1    ;check for input from KEYPAD
        ;goto   $-1     ;if NOT, keep polling
        goto    Polltime6
        swapf   PORTB, W    ;When input is detected, read it in to W
        andlw   0x0F
        btfsc   PORTB, 1    ;keep iterating until key is released
        goto $-1
        goto    CHECKPRESS6 
Polltime6   
        movlw   "T"     ;displays T for Real Time
        call    WR_DATA
        call    Realtime    ;displays Real Time
        Display Message2    ;displays B:    
        movlw   "6"     ;displays barrel #      
        call    WR_DATA     
        Display Message5 
        movfw   barrel6 ;T/S/E/HF/F
        call    Check_Type
        call    Switch_Lines
        Display Message6
        movfw   barrel6
        call    Check_Height
        Display Message7
        movfw   barrel6+3 ;ten digit first, how is this stored? Leave as O's for now
        call    WR_DATA
        movfw   barrel6+2
        call    WR_DATA
        movfw   barrel6+1
        call    WR_DATA
        Display Message8
        call    HalfS
        call    Clear_Display
        goto    POLL6       
CHECKPRESS6
BACKWARD6   ;checks if 1 was pressed
        movwf   option_temp
        xorlw   b'00000000'         ;checks to see if "1" was pressed
        btfss   STATUS,Z            ;if status Z goes to 0, it is not "1"
        goto    FORWARD6         ;if not, check to see if "2" was pressed
        call    Clear_Display   
        goto    POLL5
FORWARD6    ;checks if 2 was pressed
        movf    option_temp, W
        xorlw   b'00000001'
        btfss   STATUS,Z
        goto    POLL6 ;resume polling
        call    Clear_Display
        goto    POLL7       
        
;***************************************
; BARREL7
;***************************************

POLL7
        btfss   PORTB, 1    ;check for input from KEYPAD
        ;goto   $-1     ;if NOT, keep polling
        goto    Polltime7
        swapf   PORTB, W    ;When input is detected, read it in to W
        andlw   0x0F
        btfsc   PORTB, 1    ;keep iterating until key is released
        goto $-1
        goto    CHECKPRESS7
Polltime7   
        movlw   "T"     ;displays T for Real Time
        call    WR_DATA
        call    Realtime    ;displays Real Time
        Display Message2    ;displays B:    
        movlw   "7"     ;displays barrel #      
        call    WR_DATA     
        Display Message5 
        movfw   barrel7 ;T/S/E/HF/F
        call    Check_Type
        call    Switch_Lines
        Display Message6
        movfw   barrel7
        call    Check_Height
        Display Message7
        movfw   barrel7+3 ;ten digit first, how is this stored? Leave as O's for now
        call    WR_DATA
        movfw   barrel7+2
        call    WR_DATA
        movfw   barrel7+1
        call    WR_DATA
        Display Message8
        call    HalfS
        call    Clear_Display
        goto    POLL7
CHECKPRESS7
BACKWARD7   ;checks if 1 was pressed
        movwf   option_temp
        xorlw   b'00000000'         ;checks to see if "1" was pressed
        btfss   STATUS,Z            ;if status Z goes to 0, it is not "1"
        goto    FORWARD7         ;if not, check to see if "2" was pressed
        call    Clear_Display   
        goto    POLL6
FORWARD7    ;checks if 2 was pressed
        movf    option_temp, W
        xorlw   b'00000001'
        btfss   STATUS,Z
        goto    POLL7 ;resume polling
        call    Clear_Display
        goto    POLL1                       

        goto    $
        ;1: Stores Tall/Short Barrel, Stores E/HF/F
        ;2: Location (stores distance < 256 cm)
        ;3: Location (if distance > 256 cm)
;;          
;;      
;;


;;ShiftDisplayLeft
;       ;call       Clear_Display
;
;;      Display     Welcome_Msg2        
;;ChangeToQuestionMark
;;      movlw       b'11001011'
;;      call        WR_INS
;;      movlw       "?"
;;      call        WR_DATA
;
;
;
;;Left  movlw       b'00011000'     ;Move to the left
;;      call        WR_INS
;;      call        HalfS
;;      goto        Left            ;repeat operation
;;
;***************************************
; MAIN PROGRAM SUBROUTINES
;***************************************
        
        
;***************************************
; IR SENSOR CODE
;***************************************   
        
        
CHECK_IR1   
        ;initialize IR_DETECT
        movlw   b'0'
        movwf   IR_DETECT
        
        movlw   b'11000001' ;to select IR1
        movwf   ad_store
        movfw   ad_store
        call    IR_MAINLOOP
        return ;GO BACK TO OPERATION CODE
CHECK_IR2   
        ;initialize IR_DETECT
        movlw   b'0'
        movwf   IR_DETECT
        
        movlw   b'11001001' ;to select IR2
        movwf   ad_store
        movfw   ad_store
        call    IR_MAINLOOP
        return ;GO BACK TO OPERATION CODE
CHECK_IR3   
        ;initialize IR_DETECT
        movlw   b'0'
        movwf   IR_DETECT
        
        movlw   b'11010001' ;to select IR3
        movwf   ad_store
        movfw   ad_store
        call    IR_MAINLOOP
        return ;GO BACK TO OPERATION CODE
CHECK_IR4   
        ;initialize IR_DETECT
        movlw   b'0'
        movwf   IR_DETECT
        
        movlw   b'11011001' ;to select IR4
        movwf   ad_store
        movfw   ad_store
        call    IR_MAINLOOP
        return ;GO BACK TO OPERATION CODE
CHECK_IR5   
        
        ;initialize IR_DETECT
        movlw   b'0'
        movwf   IR_DETECT
        
        movlw   b'11100001' ;to select IR5
        movwf   ad_store
        movfw   ad_store
        call    IR_MAINLOOP          
        return ;GO BACK TO OPERATION CODE
CHECK_IR6   
        ;initialize IR_DETECT
        movlw   b'0'
        movwf   IR_DETECT
        
        movlw   b'11101001' ;to select IR6
        movwf   ad_store
        movfw   ad_store
        call    IR_MAINLOOP
        return ;GO BACK TO OPERATION CODE
CHECK_IR7   
        ;initialize IR_DETECT
        movlw   b'0'
        movwf   IR_DETECT
        
        movlw   b'11110001' ;to select IR7
        movwf   ad_store
        movfw   ad_store
        call    IR_MAINLOOP          
        return ;GO BACK TO OPERATION CODE
CHECK_IR8   
        ;initialize IR_DETECT
        movlw   b'0'
        movwf   IR_DETECT
        
        movlw   b'11111001' ;to select IR8
        movwf   ad_store
        movfw   ad_store
        call    IR_MAINLOOP          
        return ;GO BACK TO OPERATION CODE
IR_MAINLOOP
        movfw   ad_store ;storing the ADCON value
        call    AD_CONV
        movwf   voltage_IR
        call    CHECK_IR
        btfss   STATUS,C
        goto    DISPLAYCHECKHIGH
        goto    DISPLAYLOW
        return
        ;C is set when voltage >= 4.1
CHECK_IR
        movlw   b'10111101'
        subwf   voltage_IR,W
        return
        
DISPLAYLOW  

        movlw   d'0'
        movwf   lastop_IR
        movlw   b'0'
        movwf   IR_DETECT
        return
        
DISPLAYCHECKHIGH
        movfw   lastop_IR ;check if last call was a 1
        xorlw   d'1'
        btfsc   STATUS, Z
        goto INCREMENT_IR ;if it is, increment
        movlw   d'1' ;else, set lastop = 1
        movwf   lastop_IR
        movlw   d'1' ;set counter = 1
        movwf   counter_IR
        goto    IR_MAINLOOP
        ;return
        
INCREMENT_IR    
        movfw   counter_IR
        xorlw   d'4'
        btfsc   STATUS,Z
        goto    DISPLAYHIGH
        incf    counter_IR
        movfw   counter_IR
        xorlw   d'4'
        btfsc   STATUS,Z
        goto    DISPLAYHIGH
        goto    IR_MAINLOOP
        ;return
DISPLAYHIGH

        movlw   b'1'
        movwf   IR_DETECT
        return
        
;***************************************
; ULTRASONIC SENSOR CODE
;***************************************    
        
        
ULTRASONIC          
        movlw   d'16' ;initialize timer module
        movwf   T1CON
        movlw   d'0'
        movwf   TMR1L
        movlw   d'0'
        movwf   TMR1H
        
        bsf US_TRIG ;10us TRIGGER HIGH
        call    DelayL
        bcf US_TRIG ;TRIGGER LOW
        
        btfss   US_ECHO ;waiting to detect echo (HIGH)
        goto    $-1
        bsf T1CON, 0 ;turn timer on / TMR1ON=1
        btfsc   US_ECHO ;waiting for echo to go LOW
        goto    $-1
        bcf T1CON, 0 ;turn timer off
        
        movfw   TMR1L
        movwf   Time_Low
        movfw   TMR1H
        movwf   Time_High
        
        return

;;***************************************
;; ENCODER SUBROUTINE
;;***************************************
;;      
;;      btfss   PORTB, 1
;;      goto    $-1
;;      call    Clear_Display
;;      call    Distance_Count
;;      movfw   Dis_Hunds
;;      call    WR_DATA
;;      movfw   Dis_Tens
;;      call    WR_DATA
;;      movfw   Dis_Ones
;;      call    WR_DATA
;;      btfsc   PORTB, 1
;;      goto    $-1
;;      goto    TEST_ENCODER
;;      goto    $
;
;***************************************
; DISTANCE COUNT SUBROUTINE
;***************************************
Distance_Count
        ;movlw      0x0C    ;Wait to begin
        ;Keypad   
        
        movfw       Dis_Ones
        xorlw       b'00111001'
        btfsc       STATUS,Z
        goto        Skip_Ten
        incf        Dis_Ones,1
        return
        
Skip_Ten    movfw       Dis_Tens
        xorlw       b'00111001'
        btfsc       STATUS,Z
        goto        Skip_Hund
        incf        Dis_Tens,1
        movlw       b'00110000'
        movwf       Dis_Ones
        return

Skip_Hund   movfw       Dis_Hunds
        xorlw       b'00111001' ;ASCII 9
        btfsc       STATUS,Z
        goto        Skip_Thou
        incf        Dis_Hunds,1
        movlw       b'00110000'
        movwf       Dis_Ones
        movwf       Dis_Tens
        return 
        
Skip_Thou   incf        Dis_Thous,1
        movlw       b'00110000' ;ASCII 0
        movwf       Dis_Ones
        movwf       Dis_Tens
        movwf       Dis_Hunds
        return

;;***************************************
;; RETRACT ARM SUBROUTINE
;;***************************************
;
;RETRACT_ARM_BACK
;       ;bcf    DCA1 ;turn off wheel motors
;       ;bcf    DCB1 ;turn off wheel motors
;       bcf DCC1
;       bsf DCC2 ;turn on DC motor
;       ;for X seconds, need to be tested
;       call    HalfS
;       call    HalfS
;       call    HalfS
;       call    HalfS
;       
;       bcf DCC2 ;turn off DC motor
;       
;       
;       ;dont move for 3 seconds
;       call    HalfS
;       call    HalfS
;       call    HalfS
;       call    HalfS
;       call    HalfS
;       call    HalfS
;       
;       bsf DCC1
;       bcf DCC2 ;reverse arm DC direction
;       
;       
;       call    HalfS
;       call    HalfS
;       call    HalfS
;       call    HalfS
;       
;       bcf DCC1
;
;       
;       return


;*TEST RETRACT_ARM FOR DEMO*
        
;RETRACT_ARM_BACK
;       bcf DCC1
;       bsf DCC2 ;turn on DC motor
;       
;       call    HalfS
;       call    HalfS
;       call    HalfS
;       call    HalfS
;       call    HalfS
;       call    HalfS
;       call    HalfS
;       call    HalfS
;       call    HalfS
;       call    HalfS
;       
;       
;       bsf DCC1
;       bcf DCC2 ;reverse arm DC direction
;       
;       
;       call    HalfS
;       call    HalfS
;       call    HalfS
;       call    HalfS
;       call    HalfS
;       call    HalfS
;       call    HalfS
;       call    HalfS
;       call    HalfS
;       call    HalfS
;       
;
;       
;       return
;       
        
;***************************************
; CHECK DISTANCE SUBROUTINE
;***************************************
        
CHECK_DISTANCE

        movfw   Dis_Hunds ;this must be <=4
        movlw   b'00110100' ;max value for the hundreds place
        subwf   Dis_Hunds, W ;Dis_Hunds <- Dis_Hunds - 4
        return
;***************************************
; SHORTBARREL SUBROUTINE
;***************************************
        
        
SHORTBARREL
        incf    barrelnum, 1 ;increment barrel count
        
        call    CHECK_IR1 ;check if IR1 detects
        movfw   IR_DETECT
        xorlw   b'1'
        btfss   STATUS, Z
        goto    SHORTBARREL1  ;IR1 does not detect, then check IR5
        goto    SFULLORHALF ;IR1 detects, at this point, the barrel is either FULL or HALFFULL
    
SHORTBARREL1        
        call    CHECK_IR5 ;check if IR5 detects
        movfw   IR_DETECT
        xorlw   b'1'
        btfss   STATUS, Z
        goto    RECORD_SE ;IR1 and IR5 both don't detect, it is SMALL+EMPTY
        goto    SFULLORHALF  ;IR5 detects, at this point, the barrel is either FULL or HALFFULL
        
        
SFULLORHALF 
        call    CHECK_IR3 ;check if IR3 detects
        movfw   IR_DETECT
        xorlw   b'1'
        btfss   STATUS, Z
        goto    SFULLORHALF1 ;IR3 does not detect, check IR7 on the other side
        goto    RECORD_SF   ;IR3 detects, it must be SMALL + FULL
SFULLORHALF1        
        call    CHECK_IR7 ;check if IR7 detects
        movfw   IR_DETECT
        xorlw   b'1'
        btfss   STATUS, Z
        goto    RECORD_SHF ;IR3 and IR7 does not detect, but either IR1 or IR5 detected, so this must be SMALL + HALFFULL
        goto    RECORD_SF  ;IR7 detects, it must be SMALL + FULL


;***************************************
; TALLBARREL SUBROUTINE
;***************************************        
TALLBARRELL
        incf    barrelnum, 1
        
        call    CHECK_IR2 ;check if IR2 detects
        movfw   IR_DETECT
        xorlw   b'1'
        btfss   STATUS, Z
        goto    TALLBARRELL1 ;if IR2 does not detect, check IR6 on the other side of the arm
        goto    TFULLORHALF  ;if IR2 detects, the barrel is either FULL or HALFFULL
TALLBARRELL1
        call    CHECK_IR6
        movfw   IR_DETECT
        xorlw   b'1'
        btfss   STATUS, Z
        goto    RECORD_TE ;if IR6 does not detect either, it must be EMPTY
        goto    TFULLORHALF ;if IR6 detects, the barrel is either FULL or HALFFULL

TFULLORHALF 
        call    CHECK_IR4
        movfw   IR_DETECT
        xorlw   b'1'
        btfss   STATUS, Z
        goto    TFULLORHALF1 ;if IR4 does not detect, check IR8 on the other side of the arm
        goto    RECORD_TF   ;if IR4 detects, it must be TALL + FULL
TFULLORHALF1        
        call    CHECK_IR8
        movfw   IR_DETECT
        xorlw   b'1'
        btfss   STATUS, Z
        goto    RECORD_THF  ;if IR8 does not detect either, it must be TALL + HALLFULL
        goto    RECORD_TF ;if IR8 detects, it is TALL + FULL

;***************************************
; MOVE INFO TO BARREL_DATA SUBROUTINE
;***************************************
        
RECORD_SE   
        movlw   b'00001100' ;(S=1/T=0)/E/HF/F
        movwf   barrel_data ;store it so it can be recorded
        goto    RECORD              
RECORD_SHF
        movlw   b'00001010' 
        movwf   barrel_data 
        goto    RECORD
RECORD_SF
        movlw   b'00001001'
        movwf   barrel_data
        goto    RECORD

RECORD_TE   
        movlw   b'00000100'
        movwf   barrel_data
        goto    RECORD
RECORD_THF
        movlw   b'00000010'
        movwf   barrel_data
        goto    RECORD
RECORD_TF   
        movlw   b'00000001'
        movwf   barrel_data
        goto    RECORD
        
;***************************************
; MAIN RECORD
;***************************************
        
RECORD      ;main record
        ;first need to determine which barrel it is
                
B_ONE       
        movfw   barrelnum ;move barrelnum to working register
        xorlw   b'00000001' ; 1
        btfsc   STATUS, Z
        goto    RECORD_ONE
        goto    B_TWO
        
B_TWO       
        movfw   barrelnum
        xorlw   b'00000010' ; 2
        btfsc   STATUS, Z
        goto    RECORD_TWO
        goto    B_THREE

B_THREE     
        movfw   barrelnum
        xorlw   b'00000011' ;3
        btfsc   STATUS, Z
        goto    RECORD_THREE
        goto    B_FOUR
        
B_FOUR      
        movfw   barrelnum
        xorlw   b'00000100' ;4
        btfsc   STATUS, Z
        goto    RECORD_FOUR
        goto    B_FIVE
        
B_FIVE      
        movfw   barrelnum
        xorlw   b'00000101' ;5
        btfsc   STATUS, Z
        goto    RECORD_FIVE
        goto    B_SIX
        
B_SIX       
        movfw   barrelnum
        xorlw   b'00000110' ;6
        btfsc   STATUS, Z
        goto    RECORD_SIX
        goto    B_SEVEN
        
B_SEVEN     
        goto    RECORD_SEVEN ;has to be barrel 7 at this point
        
        
        
;***************************************
; RECORD WHEN BARREL NUMBER IS KNOWN
;***************************************
                
        
RECORD_ONE
        ;stores the E/HF/F bits
        movfw   barrel_data
        movwf   barrel1 ;move the data into barrel1, althought only the last three move bits are important
        goto    OPERATION_START ;go back to program
        
RECORD_TWO
        movfw   barrel_data
        movwf   barrel2 
        goto    OPERATION_START 
        
RECORD_THREE
        movfw   barrel_data
        movwf   barrel3 
        goto    OPERATION_START 
        
RECORD_FOUR
        movfw   barrel_data
        movwf   barrel4 
        goto    OPERATION_START 
        
RECORD_FIVE
        movfw   barrel_data
        movwf   barrel5 
        goto    OPERATION_START 

RECORD_SIX
        movfw   barrel_data
        movwf   barrel6 
        goto    OPERATION_START

RECORD_SEVEN
        movfw   barrel_data
        movwf   barrel7 
        goto    OPERATION_START 
        
;***************************************
; ULTRASONIC DELAYS (10 us)
;***************************************        
        
DelayL
        movlw   0x30        ; b'00110000'
        movwf   0x53        ; general purpose register
CONT3L
        decfsz  0x53, f
        goto    CONT3L
        return      
        
;***************************************
; MOTOR SUBROUTINE (PWM)
;***************************************        
        
MOTOR_ON_RC1
        movlw   b'11111111'
        movwf   CCPR2L
        bsf PORTC, 1
        return
MOTOR_ON_RC2

        movlw   b'11111111'
        movwf   CCPR1L
        
        bsf PORTC,2
        return
MOTOR_BOTH_OFF
        movlw   b'00000000'
        movwf   CCPR2L
        movwf   CCPR1L
        return
        
    
    ;100% 11111111 255
    ;80%    11000111 199
    ;60%    10010101 149
    ;0%     00000000
;***************************************
; LCD control
;***************************************
Switch_Lines
        movlw   B'11000000'
        call    WR_INS
        return

Clear_Display
        movlw   B'00000001'
        call    WR_INS
        return

;***************************************
; Delay 0.5s
;***************************************
HalfS   
    local   HalfS_0
      movlw 0x88
      movwf COUNTH
      movlw 0xBD
      movwf COUNTM
      movlw 0x03
      movwf COUNTL

HalfS_0
      decfsz COUNTH, f
      goto   $+2
      decfsz COUNTM, f
      goto   $+2
      decfsz COUNTL, f
      goto   HalfS_0

      goto $+1
      nop
      nop
        return
;***************************************
; STORING BARREL INFO ON LCD SUBROUTINE
;***************************************
        
Check_Type
CHECKE      
        movwf   barreltemp ;STORE IT TEMPORARY, LEST XORLW WILL ALTER IT
        
        ;check if barrel has been accessed
        movfw   barreltemp
        xorlw   b'01011000' ;ASCII X
        btfsc   STATUS, Z ;Z=1 if ASCII X
        goto    PRINTDEFAULT ;Z=1, so display X
        movfw   barreltemp ;Z!=1, so continue
        btfss   barreltemp,2
        goto    CHECKHF
        movlw   "E"
        call    WR_DATA
        return  

CHECKHF     
        movfw   barreltemp
        btfss   barreltemp,1
        goto    CHECKF
        movlw   "H"
        call    WR_DATA
        movlw   "F"
        call    WR_DATA
        return

CHECKF      
        ;must be FULL at this point
        movlw   "F"
        call    WR_DATA
        return
PRINTDEFAULT
        movlw   "X"
        call    WR_DATA
        return
        
Check_Height  
CHECKSHORT  
        
        movwf   barreltemp ;STORE IN HERE TEMPORARILY
        
        ;check if barrel has been accessed
        movfw   barreltemp
        xorlw   b'01011000' ;ASCII X
        btfsc   STATUS, Z ;Z=1 if ASCII X
        goto    PRINTDEFAULT1 ;Z=1, so display X
        movfw   barreltemp ;Z!=1, so continue
        btfss   barreltemp,3
        goto    CHECKTALL
        movlw   "S"
        call    WR_DATA
        movlw   " "
        call    WR_DATA
        return
CHECKTALL   ;must be TALL at this point
        movlw   "T"
        call    WR_DATA
        movlw   " "
        call    WR_DATA
        return
        
PRINTDEFAULT1
        movlw   "X"
        call    WR_DATA
        movlw   " "
        call    WR_DATA
        return
;******* LCD-related subroutines *******


    ;***********************************
InitLCD
    bcf STATUS,RP0
    bsf E     ;E default high
    
    ;Wait for LCD POR to finish (~15ms)
    call lcdLongDelay
    call lcdLongDelay
    call lcdLongDelay

    ;Ensure 8-bit mode first (no way to immediately guarantee 4-bit mode)
    ; -> Send b'0011' 3 times
    movlw   b'00110011'
    call    WR_INS
    call lcdLongDelay
    call lcdLongDelay
    movlw   b'00110010'
    call    WR_INS
    call lcdLongDelay
    call lcdLongDelay

    ; 4 bits, 2 lines, 5x7 dots
    movlw   b'00101000'
    call    WR_INS
    call lcdLongDelay
    call lcdLongDelay

    ; display on/off
    movlw   b'00001100'
    call    WR_INS
    call lcdLongDelay
    call lcdLongDelay
    
    ; Entry mode
    movlw   b'00000110'
    call    WR_INS
    call lcdLongDelay
    call lcdLongDelay

    ; Clear ram
    movlw   b'00000001'
    call    WR_INS
    call lcdLongDelay
    call lcdLongDelay
    return
    ;************************************

    ;ClrLCD: Clear the LCD display
ClrLCD
    movlw   B'00000001'
    call    WR_INS
    return

    ;****************************************
    ; Write command to LCD - Input : W , output : -
    ;****************************************
WR_INS
    bcf     RS              ;clear RS
    movwf   com             ;W --> com
    andlw   0xF0            ;mask 4 bits MSB w = X0
    movwf   PORTD           ;Send 4 bits MSB
    bsf     E               ;
    call    lcdLongDelay    ;__    __
    bcf     E               ;  |__|
    swapf   com,w
    andlw   0xF0            ;1111 0010
    movwf   PORTD           ;send 4 bits LSB
    bsf     E               ;
    call    lcdLongDelay    ;__    __
    bcf     E               ;  |__|
    call    lcdLongDelay
    return

    ;****************************************
    ; Write data to LCD - Input : W , output : -
    ;****************************************
WR_DATA
    bsf     RS              
    movwf   dat
    movf    dat,w
    andlw   0xF0        
    addlw   4
    movwf   PORTD       
    bsf     E               ;
    call    lcdLongDelay    ;__    __
    bcf     E               ;  |__|
    swapf   dat,w
    andlw   0xF0        
    addlw   4
    movwf   PORTD       
    bsf     E               ;
    call    lcdLongDelay    ;__    __
    bcf     E               ;  |__|
    return

lcdLongDelay
    movlw d'20'
    movwf lcd_d2
LLD_LOOP
    LCD_DELAY
    decfsz lcd_d2,f
    goto LLD_LOOP
    return
;*********
; BIN2BCD
; Converts a binary number to ASCII
; characters for display on the LCD
; Written by: A. Borowski
; Sourced from: piclist.com --> 8 bit to ASCII Decimal 3 digits
;**********
BIN2BCD
    movlw 8
    movwf count
    clrf huns
    clrf tens
    clrf ones

BCDADD3

    movlw 5
    subwf huns, 0
    btfsc STATUS, C
    CALL ADD3HUNS

    movlw 5
    subwf tens, 0
    btfsc STATUS, C
    CALL ADD3TENS

    movlw 5
    subwf ones, 0
    btfsc STATUS, C
    CALL ADD3ONES

    decf count, 1
    bcf STATUS, C
    rlf binary_num, 1
    rlf ones, 1
    btfsc ones,4 ;
    CALL CARRYONES
    rlf tens, 1

    btfsc tens,4 ;
    CALL CARRYTENS
    rlf huns,1
    bcf STATUS, C

    movf count, 0
    btfss STATUS, Z
    goto BCDADD3

    movf huns, 0 ; add ASCII Offset
    addlw h'30'
    movwf huns

    movf tens, 0 ; add ASCII Offset
    addlw h'30'
    movwf tens

    movf ones, 0 ; add ASCII Offset
    addlw h'30'
    movwf ones
    return

ADD3HUNS
    movlw 3
    addwf huns,1
    return

ADD3TENS
    movlw 3
    addwf tens,1
    return

ADD3ONES
    movlw 3
    addwf ones,1
    return

    
    
    
    
CARRYONES
    bcf ones, 4
    bsf STATUS, C
    return

CARRYTENS
    bcf tens, 4
    bsf STATUS, C
    return    
 
     ;call  AD_CONV
     ;call  WR_DATA
     ;call  HalfS
     ;call  Clear_Display
     ;goto  Main
     
;*********
; ADC
;**********    
    goto    INITA
INITA   bsf STATUS,RP0 ;select bank 1
    bcf INTCON,GIE ;disable global interrupt
    movlw   B'00000000' ;configure ADCON1
    movwf   ADCON1
    clrf    TRISB ;configure PORTB as output
    bcf STATUS,RP0 ;select bank 0
    goto    ADSTART
;***************************************************************
; MAIN PROGRAM
;***************************************************************
ADSTART call    AD_CONV ;call the A2D subroutine
    movwf   PORTB ;display the high 8-bit result to the LEDs
ENDLP   goto    ENDLP ;endless loop
;***************************************************************
; AD CONVERT ROUTINE
;***************************************************************
AD_CONV ;movlw  B'10000001' ;configure ADCON0
    movwf   ADCON0
    call    TIM20 ;wait for required acquisition time
    bsf ADCON0,GO ;start the conversion
WAIT    btfsc   ADCON0,GO ;wait until the conversion is completed
    goto    WAIT ;poll the GO bit in ADCON0
    movf    ADRESH,W ;move the high 8-bit to W
    return
;**************************************************************
; TIME DELAY ROUTINE FOR 20us
;
; - delay of 400 cycles
; - 400*0.05us = 20us
;**************************************************************
TIM20   movlw   084H ;1 cycle
    movwf   TIMCNT ;1 cycle
TIMLP   decfsz  TIMCNT,F ;(3*132)-1 = 395 cycles
    goto    TIMLP
    nop ;1 cycle
    return  ;2 cycles    

;***************************************
; Real Time
;***************************************    
    
show_RTC
        ;clear LCD screen
        movlw   b'00000001'
        call    WR_INS

        ;Get year
        ;movlw  "2"             ;First line shows 20**/**/**
        ;call   WR_DATA
        ;movlw  "0"
        ;call   WR_DATA
        ;rtc_read   0x06        ;Read Address 0x06 from DS1307---year
        ;movfw  0x77
        ;call   WR_DATA
        ;movfw  0x78
        ;call   WR_DATA

        ;movlw  "/"
        ;call   WR_DATA

        ;Get month
        ;rtc_read   0x05        ;Read Address 0x05 from DS1307---month
        ;movfw  0x77
        ;call   WR_DATA
        ;movfw  0x78
        ;call   WR_DATA

        ;movlw  "/"
        ;call   WR_DATA

        ;Get day
        ;rtc_read   0x04        ;Read Address 0x04 from DS1307---day
        ;movfw  0x77
        ;call   WR_DATA
        ;movfw  0x78
        ;call   WR_DATA

        ;movlw  B'11000000'     ;Next line displays (hour):(min):(sec) **:**:**
        ;call   WR_INS          ;NEXT LINE

        ;Get hour
        ;rtc_read   0x02        ;Read Address 0x02 from DS1307---hour
        ;movfw  0x77
        ;call   WR_DATA
        ;movfw  0x78
        ;call   WR_DATA
        ;movlw          ":"
        ;call   WR_DATA


        
        ;Get minute
Realtime    
        rtc_read    0x01        ;Read Address 0x01 from DS1307---min
        movfw   0x77
        call    WR_DATA
        movfw   0x78
        call    WR_DATA     
        movlw           ":"
        call    WR_DATA
        
        ;Get seconds
        rtc_read    0x00        ;Read Address 0x00 from DS1307---seconds
        movfw   0x77
        call    WR_DATA
        movfw   0x78
        call    WR_DATA
        return
        
        call    OneS            ;Delay for exactly one seconds and read DS1307 again
        goto    show_RTC
        
Operationtime   
        rtc_read    0x01        ;Read Address 0x01 from DS1307---min
        movfw   0x77
        movwf   min 
        ;call   WR_DATA
        movfw   0x78
        movwf   min+1
        ;call   WR_DATA     
        ;movlw          ":"
        ;call   WR_DATA
        
        ;Get seconds
        rtc_read    0x00        ;Read Address 0x00 from DS1307---seconds
        movfw   0x77
        movwf   sec
        ;call   WR_DATA
        movfw   0x78
        movwf   sec+1
        ;call   WR_DATA
        return
        
        ;call   OneS            ;Delay for exactly one seconds and read DS1307 again
        ;goto   show_RTC
        

     
;;***************************************
;; Setup RTC with time defined by user
;;***************************************
set_rtc_time

        ;rtc_resetAll   ;reset rtc

        ;rtc_set    0x00,   B'10000000'

        ;set time 
        ;rtc_set    0x06,   B'00010000'     ; Year
        ;rtc_set    0x05,   B'00000100'     ; Month
        ;rtc_set    0x04,   B'00000110'     ; Date
        ;rtc_set    0x03,   B'00000010'     ; Day
        ;rtc_set    0x02,   B'00010010'     ; Hours
        ;rtc_set    0x01,   B'00110000'     ; Minutes
        ;rtc_set    0x00,   B'00000000'     ; Seconds
        ;return

;***************************************
; Delay 1s
;***************************************
OneS
        local   OneS_0
      movlw 0x10
      movwf COUNTH1
      movlw 0x7A
      movwf COUNTM1
      movlw 0x06
      movwf COUNTL1

OneS_0
      decfsz COUNTH1, f
      goto   $+2
      decfsz COUNTM1, f
      goto   $+2
      decfsz COUNTL1, f
      goto   OneS_0

      goto $+1
      nop
      nop
        return
        
    
    END
