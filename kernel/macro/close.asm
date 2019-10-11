;===============================================================================
; Copyright (C) by Blackend.dev
;===============================================================================

%MACRO	macro_close	2
	push	rax

.1:	; zamknij dostęp do %1
	mov	al,	STATIC_TRUE
	lock	xchg	byte [%1 + %2],	al
	test	al,	al
	jz	.1	; spróbuj raz jeszcze

	pop	rax
%ENDMACRO
