;===============================================================================
; Copyright (C) by Blackend.dev
;===============================================================================

kernel_init_video:
	; wyczyść przestrzeń pamięci trybu tekstowego
	call	kernel_video_dump
