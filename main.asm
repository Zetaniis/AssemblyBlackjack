/*
Blackjack 
Made by Piotr Data and Duy Thang

Game rules:
Player draws a random value from 1-11 as many times as he wants and then folds. Random value is generated for house and then compared with player's. 
Bigger value that doesnt excced 21 wins. Led represtenting the winner lights up. After winning 4 rounds the game resets.

Port a to LED;	Port d (p2, p3) to control interrupt;	Port d (p4 -p7) to 7segment control;	Port b to 7segment output
 */ 


.include "m32def.inc"
.cseg
.org 0
jmp start

.org INT0addr
jmp event2		;Keyboad External Interrupt Request 0

.org INT1addr
jmp event1		;Keyboad External Interrupt Request 1


.def playerScore=r18
.def playerRounds = r19
.def houseScore = r20
.def houseRounds = r21
.def event = r22
.def rand = r23
.def randBool = r24

.org 0x60 

segWin: .DB 0x1E, 0x3C, 0x10, 0x15			//7 seg win screen  ///DEPRECATED///
segLose: .DB 0x0E, 0x3D, 0x5B, 0x4F			//7 seg lose screen ///DEPRECATED///
			 //0    //1    //2    //3    //4    //5     //6    //7    //8    //9    
numbers: .DB 0x7e,  0x30, 0x6d,   0x79,  0x33,  0x5b,   0x5f,  0x70,  0x7F,  0x7B

.org 0x100 	
; Main program start
start:
setup:	
	ldi r16,high(RAMEND)		// Stack pointer setup
	out SPH,r16 
	ldi r16,low(RAMEND)
	out SPL,r16

	;Set up port A as output for LED controls
	ldi r16, 0xFF
	out ddra, r16

	; Enable Int1, Int0
	ldi r16, 0b11000000			;(1<<int1) && (1<<int0)
	out gicr, r16

	; Clear intf1, inf0 flag
	ldi r16, 0x00
	ldi r16, 0b11000000		;(1 << intf1) && (1 << intf0)
	out gifr, r16

	; Set Int1, Int0 active on rising edge
	ldi r16, 0x00
	ldi r16, 0b00001111	;(0<<isc11) && (1<<isc10)  && (0<<isc01) && (1<<isc00)
	out mcucr, r16

	ldi r16, 0xff
	out ddrb, r16					//Port b for 7segment output

	ldi r16, 0xf0	
	out ddrd, r16					//Port d 2,3 interrupt, 4-7 segment control

	ldi r16, 0x00
	out portb, r16

	ldi r16, 0x0f
	out portd, r16

	ldi playerScore, 0				//Setting up the initial values of variables
	ldi playerRounds, 0
	ldi houseScore, 0
	ldi houseRounds, 0
	ldi event, 0xff
	ldi rand, 0x00					//Random seed
	ldi randBool, 0x00				//Bool used for breaking the breaks(brne brge) that is used to stop the game after folding and stop the random number generation

	;Global Enable Interrupt
	sei

rand1:			
									//Random number generation until button is pressed
	inc rand
	cpi randBool, 0x01
	brne rand1

loop:
	inc rand
					
	call seg						//call for showing numbers on 7segments
	nop
	nop
	nop
			
	call ledScore					//call for showing rounds score on leds

	rjmp loop

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

;Keypad Interrupt Service Routine
event1:						//Interrupt used for drawing the card by player  
							//Value of event is used for checking how the game is progressing:
							//0xff - start of the game, 0x00 - default state
							//0x03 - playerWin(after 4 rounds), 0x04 - playerLoses(after 4 rounds), 0x05 - intermission inbetween the rounds(before playerWin) , 0x06 - intermission inbetween the rounds(before playerLose)
		nop
		cli //Disabling interrupts
		call waitD
		push r17


		cpi event, 0x06				//Resetting the whole game after displaying the final round 
		brne restarting
		jmp setup
restarting:
		cpi event, 0x05
		brne restartingEnd
		jmp setup
restartingEnd:

		cpi randBool, 0x00
		brne roundReset

		ldi randBool, 0x01
		ldi playerScore, 0						//Resetting cards scores
		ldi houseScore, 0
		rjmp endEvent
		 
roundReset:
		cpi event, 0x03				//Resetting all scores
		brne resetFinal
		ldi playerScore, 0
		ldi playerRounds, 0
		ldi houseScore, 0
		ldi houseRounds, 0
		;rjmp endEvent
resetFinal:
		cpi event, 0x04
		brne resetFinalEnd
		ldi playerScore, 0
		ldi playerRounds, 0
		ldi houseScore, 0
		ldi houseRounds, 0
		;rjmp endEvent
resetFinalEnd:

		call modPlayer						//Add to playerScore a random value from 1 to 11
		ldi r17, 1
		add playerScore, r17

		ldi r17, 137						//Simple rand function for randoming next draws from seed
		mul rand, r17
		mov rand, r0
		ldi r17, 131
		add rand, r17

		cpi playerScore, 22
		brge playerLoses						//If player has more than 21 score he losses, program goes to lose event
		rjmp endCon

	playerWins:									//Adding to round score to player
		lsl playerRounds
		inc playerRounds	
		ldi randBool, 0x00
		rjmp endCon

	playerLoses:								//Adding to round score to house
		lsl houseRounds
		inc houseRounds
		ldi randBool, 0x00
		rjmp endCon

	endCon:										// Checking for the 4 rounds won from either house or player
		cpi houseRounds, 15
		brne playerWinCond
		ldi event, 0x06	
		ldi randBool, 0x00
		lsl houseRounds
		inc houseRounds
		call ledScore
		nop
		rjmp endEvent

	playerWinCond:
		cpi playerRounds, 15
		brne endEvent
		ldi event, 0x05
		ldi randBool, 0x00
		lsl playerRounds
		inc playerRounds
		call ledScore
		nop
	endEvent:
	
	ldi r16,  0b10000000				
	out gifr, r16						//Clearing intf1 flag


	call waitD

		

		pop r17
		sei
	reti

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
					// frist int neeeds to be divided in two respectively into draw and fold phase (cuz cant compare value from gifr)
;Keypad Interrupt Service Routine
event2:						//Interrupt used for folding, randing a house value and comparison
		nop
		
		;Disable interrupts
		cli
		call waitD
		push r17

		cpi event, 0x06			//Resetting the whole game after displaying the final round 
		brne restarting1
		jmp setup
restarting1:
		cpi event, 0x05
		brne restartingEnd1
		jmp setup
restartingEnd1:
		cpi randBool, 0x00
		brne roundReset1
		
		ldi randBool, 0x01
		ldi playerScore, 0						//Resetting cards scores
		ldi houseScore, 0
		rjmp endEvent1

roundReset1:
		cpi event, 0x03				//Resetting all scores
		brne resetFinal1
		ldi playerScore, 0
		ldi playerRounds, 0
		ldi houseScore, 0
		ldi houseRounds, 0
resetFinal1:
		cpi event, 0x04
		brne resetFinalEnd1
		ldi playerScore, 0
		ldi playerRounds, 0
		ldi houseScore, 0
		ldi houseRounds, 0
resetFinalEnd1:

		call modHouse

		ldi r17, 4
		add houseScore, r17							//Offsetting for the range of 5 - 21

		ldi r17, 137								//Simple rand function for randoming next draws from seed
		mul rand, r17
		mov rand, r0
		ldi r17, 131
		add rand, r17


		cp  houseScore, playerScore					//Compare the values for this round
		brge playerLoses1							

	playerWins1:									//Adding to round score to player
		lsl playerRounds
		inc playerRounds		
		ldi randBool, 0x00
		rjmp endCon1

	playerLoses1:									//Adding to round score to house
		lsl houseRounds
		inc houseRounds
		ldi randBool, 0x00
		rjmp endCon1

	endCon1:										//Checking for the 4 rounds won from either house or player
		cpi houseRounds, 15
		brne playerWinCond1
		ldi event, 0x06
		call ledScore
		rjmp endEvent1

	playerWinCond1:
		cpi playerRounds, 15
		brne endEvent1
		ldi event, 0x05
	call ledScore
	nop

	endEvent1:

	ldi r16,  0b01000000			//Clearing intf0 flag
	out gifr, r16

	call waitD

	pop r17
	sei
	reti

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////


wait:						//Wait routine
	push r16
	push r17
	push r18

	ldi R16, 2
	loop1:
		ldi R17, 2
		loop2: 
			ldi R18, 100
			loop3:
				dec R18
				brne loop3
			dec R17
			brne loop2
		dec R16
		brne loop1
		pop r18
		pop r17
		pop r16
	ret

	////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

	waitD:					//Wait routine for switch debouncing
	push r16
	push r17
	push r18

	ldi R16, 20
	loop1D:
		ldi R17, 20
		loop2D: 
			ldi R18, 200
			loop3D:
				dec R18
				brne loop3D
			dec R17
			brne loop2D
		dec R16
		brne loop1D
		pop r18
		pop r17
		pop r16
	ret


////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

ledScore:					//Function outputting the rounds won by player and house
	push r17

	mov r17,  houseRounds 
	lsl r17
	lsl r17
	lsl r17
	lsl r17
	add r17,  playerRounds

	out porta, r17

	pop r17
	ret

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

modPlayer:					//Function drawing the value of houseScore 0 - 11 that is later incremented by one to not add 0 
	push r16
	mov r16, rand
modPlayerCon:
    subi r16, 11
    cpi  r16, 11
    brsh modPlayerCon
	add playerScore, r16
	pop r16 
ret 

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

modHouse:					//Function drawing the value of houseScore 0 - 18 that is later incremented to not add 0 
	push r16
	mov r16, rand
modHouseCon:
	subi r16, 18
	cpi r16, 18
	brsh modHouseCon
	add houseScore, r16
	pop r16
ret

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

mod10:						//Function outputting the decimal and unity value of some number r16 - unity value, r17 - decimal value
	cpi r16, 10
	brlt mod10end

	subi r16, 10
	inc r17
	cpi r16, 10
	brsh mod10
mod10end:
ret

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

seg:
	cli
	push r24
	push r25
	push r26
	push r27

										//Case with event to check what to show on 7seg ///DEPRECATED///
	cpi event, 0x03
	breq winSeg

	cpi event, 0x04
	breq winSeg
	
		
	ldi r25, 0b00010000					//Register used to control which segment should light up

l1:
	ldi r16, 0x00
	ldi r17, 0x00

	ldi zl, low(2*numbers)				//Loading the numbers table
	ldi zh, high(2*numbers)
	 
	com r25
	out portd, r25						//Controlling the segment number
	com r25
										//Case statement here for checking the segment and setting appropriate values
	cpi r25, 0b00010000			
	brne cpi2
	mov r16, playerScore
	call mod10
	mov r28, r16						//Loading up the decimal value of playerScore
	rjmp cpiEnd

cpi2:
	cpi r25, 0b00100000
	brne cpi3
	mov r16, playerScore
	call mod10
	mov r28, r17						//Loading up the unity value of playerScore
	rjmp cpiEnd

cpi3:
	cpi r25, 0b01000000
	brne cpi4
	mov r16, houseScore
	call mod10
	mov r28, r16						//Loading up the decimal value of houseScore
	rjmp cpiEnd

cpi4:
	cpi r25, 0b10000000
	;brne endSeg
	mov r16, houseScore
	call mod10
	mov r28, r17						//Loading up the unity value of houseScore
	

cpiEnd:

	ldi r27, 0x01 
	add r28, r27 
l2:										//Going through the numbers table to get the appropriate one
		lpm r24, z+ 
		dec r28
		brne l2
	com r24

	out portb, r24						//Outing the segment number value
	call wait

	lsl r25								//Shifting the register to prepare for outputting the next segment

	cpi r25, 0b00000000
	brne l1
	rjmp endSeg

winSeg:		
///DEPRECATED///DEPRECATED///DEPRECATED///DEPRECATED///DEPRECATED///DEPRECATED///DEPRECATED///DEPRECATED///DEPRECATED///DEPRECATED///DEPRECATED///DEPRECATED/////DEPRECATED///

	cpi event, 0x04
	breq loseSeg
	
	ldi r25, 0b00010000

win1:									

	ldi zl, low(2*segWin) 
	ldi zh, high(2*segWin)
	
	 
	com r25
	out portd, r25
	com r25

	ldi r27, 0x01 
	add r28, r27 
win2:
		lpm r24, z+ 
		dec r28
		brne win2
	com r24
	
	out portb, r24 
	call wait

	lsl r25
	cpi r25, 16
	brne win1
	rjmp endSeg

loseSeg:
	
	cpi event, 0x04
	brne endSeg

	ldi r25, 0b00010000

lose1:									

	ldi zl, low(2*segLose) 
	ldi zh, high(2*segLose)
	
	 
	com r25
	out portd, r25		
	com r25

	ldi r27, 0x01
	add r28, r27
lose2:
		lpm r24, z+ 
		dec r28
		brne lose2
	com r24
	out portb, r24 
	call wait
	
	lsl r25
	cpi r25, 0b10000000
	brne lose1
///DEPRECATED///DEPRECATED///DEPRECATED///DEPRECATED///DEPRECATED///DEPRECATED///DEPRECATED///DEPRECATED///DEPRECATED///DEPRECATED///DEPRECATED///DEPRECATED///DEPRECATED///

endSeg: 
	pop r27
	pop r26
	pop r25
	pop r24
	sei
	ret

	////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////