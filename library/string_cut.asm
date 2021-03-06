;===============================================================================
; Copyright (C) by Blackend.dev
;===============================================================================

;===============================================================================
; wejście:
;	al - separator
;	rcx - ilość znaków w ciągu
;	rsi - wskaźnik do ciągu
; wyjście:
;	rcx - ilość znaków w słowie
library_string_cut:
	; zachowaj oryginalne rejestry
	push	rsi
	push	rcx

.loop:
	; koniec ciagu?
	cmp	byte [rsi],	STATIC_ASCII_TERMINATOR
	je	.end	; tak

	; znaleziono separator
	cmp	byte [rsi],	al
	je	.end	; tak, koniec procedury

	; zwiększ licznik i sprawdź następny znak
	inc	rsi

	; sprawdzić następny znak ciągu?
	dec	rcx
	jnz	.loop

.end:
	; zwróć ilość znaków w słowie
	sub	qword [rsp],	rcx

	; przywróć oryginalne rejestry
	pop	rcx
	pop	rsi

	; powrót z procedury
	ret

	; macro_debug	"library_string_cut"
