;================================================================================
; Copyright (C) by Blackend.dev
;================================================================================

	;-----------------------------------------------------------------------
	; stałe, zmienne, globalne, struktury, obiekty itp.
	;-----------------------------------------------------------------------
	%include	"zero/config.asm"
	;-----------------------------------------------------------------------

;===============================================================================
; 16 bitowy kod programu rozruchowego ==========================================
;===============================================================================
[BITS 16]

; pozycja kodu w przestrzeni segmentu CS
[ORG STATIC_ZERO_base_address]

zero:
	;-----------------------------------------------------------------------
	; przygotuj 16 bitowe środowisko produkcyjne
	;-----------------------------------------------------------------------

	; wyłącz przerwania (modyfikujemy rejestry segmentowe)
	cli

	; ustaw adres segmentu kodu (CS) na początek pamięci fizycznej
	jmp	0x0000:.repair_cs

.repair_cs:
	; ustaw adresy segmentów danych (DS), ekstra (ES) i stosu (SS) na początek pamięci fizycznej
	xor	ax,	ax
	mov	ds,	ax	; segment danych
	mov	es,	ax	; segment ekstra
	mov	ss,	ax	; segment stosu

	; ustaw wskaźnik szczytu stosu na gwarantowaną wolną przestrzeń pamięci
	mov	sp,	STATIC_ZERO_stack

	; wyłącz Direction Flag
	cld

	;-----------------------------------------------------------------------
	; wyłącz przerwanie IRQ0 na kontrolerze PIT, jądro systemu skonfiguruje i uruchomi wg. własnych potrzeb
	;-----------------------------------------------------------------------
	mov	al,	STATIC_EMPTY	; Channel (00b), Access (11b), Operating (000b), Binary Mode (0b)
	out	DRIVER_PIT_PORT_command,	al

	; włącz "pozostałe" przerwania
	sti

	;-----------------------------------------------------------------------
	; wyczyść ekran inicjując ponownie tryb tekstowy (80x25 znaków)
	;-----------------------------------------------------------------------
	mov	ax,	0x0003
	int	0x10

	;-----------------------------------------------------------------------
	; wczytaj kod jądra systemu do przestrzeni pamięci fizycznej
	;-----------------------------------------------------------------------
	mov	ah,	0x42
	mov	si,	zero_table_disk_address_packet
	int	0x13

	; komunikat błędu: błąd odczytu z nośnika
	mov	si,	STATIC_ZERO_ERROR_disk

	; opracja odczytu wykonana poprawnie?
	jc	zero_panic	; nie

	;-----------------------------------------------------------------------
	; przygotuj mapę pamięci za pomocą funkcji BIOSu
	; http://www.ctyme.com/intr/rb-1741.htm
	;-----------------------------------------------------------------------
	xor	ebx,	ebx	; pozpocznij mapowanie od początku przestrzeni fizycznej pamięci
	mov	edx,	0x534D4150	; ciąg znaków "SMAP", specjalna wartość wymagana przez procedurę

	; komunikat błędu: błąd mapowania przestrzeni pamięci
	mov	si,	STATIC_ZERO_ERROR_memory

	; utwórz mapę pamięci pod fizycznym adresem 0x0000:0x1000
	mov	edi,	STATIC_ZERO_memory_map

.memory:
	; rozmiar wpisu
	mov	eax,	0x14
	stosd

	; pobierz informacje o przestrzeni pamięci
	mov	eax,	0xE820	; funkcja Get System Memory Map
	mov	ecx,	0x14	; rozmiar wiersza w Bajtach, generowanej tablicy
	int	0x15

	; błąd podczas generowania?
	jc	zero_panic	; tak

	; przesuń wskaźnik do następnego wiersza
	add	edi,	0x14

	; koniec wierszy generowanej tablicy?
	test	ebx,	ebx
	jnz	.memory	; nie

	;-----------------------------------------------------------------------
	; wyłącz wszystkie przerwania na kontrolerze PIC, jądro systemu skonfiguruje i uruchomi wg. własnych potrzeb
	;-----------------------------------------------------------------------
	mov	al,	0xFF
	out	DRIVER_PIC_PORT_SLAVE_data,	al	; Slave
	out	DRIVER_PIC_PORT_MASTER_data,	al	; Master

	;-----------------------------------------------------------------------
	; przełącz w liniowy tryb graficzny
	;-----------------------------------------------------------------------

	; pobierz dostępne tryby graficzne
	mov	ax,	0x4F00
	mov	si,	STATIC_ZERO_ERROR_video
	mov	di,	STATIC_ZERO_video_vga_info_block
	int	0x10

	; funkcja wywołana prawidłowo?
	test	ax,	0x4F00
	jnz	zero_panic	; nie

	; przeszukaj tablicę dostępnych trybów za porządanym
	mov	esi,	dword [di + STATIC_ZERO_VIDEO_STRUCTURE_VGA_INFO_BLOCK.video_mode_ptr]

.loop:
	; koniec tablicy?
	cmp	word [esi],	0xFFFF
	je	.error	; tak

	; pobierz właściwości danego trybu graficznego
	mov	ax,	0x4F01
	mov	cx,	word [esi]
	mov	di,	STATIC_ZERO_video_mode_info_block
	int	0x10

	; oczekiwana szerokość w pikselach?
	cmp	word [di + STATIC_ZERO_VIDEO_STRUCTURE_MODE_INFO_BLOCK.x_resolution],	MULTIBOOT_VIDEO_WIDTH_pixel
	jne	.next	; nie

	; oczekiwana wysokość w pikselach?
	cmp	word [di + STATIC_ZERO_VIDEO_STRUCTURE_MODE_INFO_BLOCK.y_resolution],	MULTIBOOT_VIDEO_HEIGHT_pixel
	jne	.next	; nie

	; oczekiwana głębia kolorów?
	cmp	byte [di + STATIC_ZERO_VIDEO_STRUCTURE_MODE_INFO_BLOCK.bits_per_pixel],	STATIC_ZERO_VIDEO_DEPTH_bit
	je	.found	; tak

.next:
	; przesuń wskaźnik na następny wpis
	add	esi,	STATIC_WORD_SIZE_byte

	; sprawdź następny tryb
	jmp	.loop

.error:
	; wyświetl kod błędu
	mov	si,	STATIC_ZERO_ERROR_video
	jmp	zero_panic

.found:
	; włącz dany tryb graficzny
	mov	ax,	0x4F02
	mov	bx,	word [esi]
	or	bx,	STATIC_ZERO_VIDEO_MODE_linear | STATIC_ZERO_VIDEO_MODE_clean
	int	0x10

	; operacja wykonana pomyślnie?
	test	ah,	ah
	jnz	.error	; nie

	; wyłącz przerwania, jeśli program rozruchowy jest w trybie 16 bitowym
	; zostaną one przywrócone
	cli

	; załaduj globalną tablicę deskryptorów dla trybu 32 bitowego
	lgdt	[zero_header_gdt_32bit]

	; przełącz procesor w tryb chroniony
	mov	eax,	cr0
	bts	eax,	0	; włącz pierwszy bit rejestru cr0
	mov	cr0,	eax

	; skocz do 32 bitowego kodu
	jmp	long 0x0008:zero_protected_mode

;-------------------------------------------------------------------------------
; wejście:
;	si - kod błędu w postaci znaku ASCII
zero_panic:
	; ustaw segment danych (DS) na przestrzeń pamięci ekranu trybu tekstowego
	mov	ax,	0xB800
	mov	ds,	ax

	; wyświetl kod błędu
	mov	word [ds:0x0000],	si

	; zatrzymaj dalsze wykonywanie kodu programu rozruchowego
	jmp	$

;-------------------------------------------------------------------------------
; wyjście:
;	Flaga ZF, jeśli linia A20 otwarta
zero_line_a20_check:
	; zapamiętaj adres segmentu danych
	push	ds

	; ustaw semgent danych na koniec pamięci fizycznej 0xFFFF0
	mov	ax,	0xFFFF
	mov	ds,	ax

	; pobierz 4 Bajty spod adresu 0x107C00
	mov	ebx,	dword [ds:STATIC_ZERO_base_address + 0x10]

	; przywróć adres segmentu danych
	pop	ds

	; sprawdź czy pobrane 4 Bajty są identyczne jak w programie rozruchowym Zero
	test	ebx,	dword [ds:STATIC_ZERO_base_address]

	; powrót z procedury
	ret

;===============================================================================
zero_ps2_keyboard_in:
	; pobierz status bufora klawiatury do al
	in	al,	0x64
	test	al,	2	; sprawdź czy drugi bit jest równy zero

	; jeśli nie, powtórz operacje
	jnz	zero_ps2_keyboard_in

	; powrót z procedury
	ret

;===============================================================================
zero_ps2_keyboard_out:
	; pobierz status bufora klawiatury do al
	in	al,	0x64
	test	al,	1	; sprawdź czy pierwszy bit jest równy zero

	; jeśli nie, powtórz operacje
	jz	zero_ps2_keyboard_out

	; powrót z procedury
	ret

;===============================================================================
; 32 bitowy kod programu rozruchowego ==========================================
;===============================================================================
[BITS 32]

zero_protected_mode:
	; ustaw deskryptory danych, ekstra i stosu na przestrzeń danych
	mov	ax,	0x10
	mov	ds,	ax	; segment danych
	mov	es,	ax	; segment ekstra
	mov	ss,	ax	; segment stosu

	;-----------------------------------------------------------------------
	; utwórz nagłówek Multiboot (wersja 0.6.96)
	;-----------------------------------------------------------------------

	; wylicz rozmiar utworzonej mapy pamięci w Bajtach
	mov	ecx,	edi
	sub	ecx,	STATIC_ZERO_memory_map

	; nagłówek utwórz za tablicą werktorów przerwań BIOSu
	mov	edi,	STATIC_ZERO_multiboot_header

	; flagi: udostępniono mapę pamięci i framebuffer
	mov	dword [edi + STATIC_MULTIBOOT_header.flags],	STATIC_MULTIBOOT_HEADER_FLAG_memory_map | STATIC_MULTIBOOT_HEADER_FLAG_video

	; rozmiar i adres mapy pamięci
	mov	dword [edi + STATIC_MULTIBOOT_header.mmap_length],	ecx
	mov	dword [edi + STATIC_MULTIBOOT_header.mmap_addr],	STATIC_ZERO_memory_map

	; właściwości przestrzeni pamięci karty graficznej
	mov	eax,	dword [STATIC_ZERO_video_mode_info_block + STATIC_ZERO_VIDEO_STRUCTURE_MODE_INFO_BLOCK.physical_base_address]
	mov	dword [edi + STATIC_MULTIBOOT_header.framebuffer_addr],	eax
	mov	dword [edi + STATIC_MULTIBOOT_header.framebuffer_width],	MULTIBOOT_VIDEO_WIDTH_pixel
	mov	dword [edi + STATIC_MULTIBOOT_header.framebuffer_height],	MULTIBOOT_VIDEO_HEIGHT_pixel
	mov	byte [edi + STATIC_MULTIBOOT_header.framebuffer_bpp],	STATIC_ZERO_VIDEO_DEPTH_bit
	mov	byte [edi + STATIC_MULTIBOOT_header.framebuffer_type],	STATIC_EMPTY	; indeksowany zestaw kolorów

	;-----------------------------------------------------------------------
	; przesuń kod jądra systemu do przestrzeni pamięci fizycznej pod adresem 0x00100000
	;-----------------------------------------------------------------------
	mov	esi,	STATIC_ZERO_kernel_address << STATIC_SEGMENT_to_pointer
	mov	edi,	STATIC_ZERO_kernel_address << STATIC_SEGMENT_to_pointer << STATIC_SEGMENT_to_pointer
	mov	ecx,	(file_kernel_end - file_kernel) / 0x04
	rep	movsd

	; zwróć informacje o adresie nagłówka multiboot
	mov	ebx,	STATIC_ZERO_multiboot_header

	; wywołaj kod jądra systemu
	jmp	STATIC_ZERO_kernel_address << STATIC_SEGMENT_to_pointer << STATIC_SEGMENT_to_pointer

;-------------------------------------------------------------------------------
; format danych w postaci tablicy, wykorzystywany przez funkcję AH=0x42, przerwanie 0x13
; http://www.ctyme.com/intr/rb-0708.htm
;-------------------------------------------------------------------------------
; wszystkie tablice trzymamy pod pełnym adresem
align 0x04
zero_table_disk_address_packet:
			db	0x10		; rozmiar tablicy
			db	STATIC_EMPTY	; wartość zastrzeżona
			dw	(file_kernel_end - file_kernel) / STATIC_SECTOR_SIZE_byte	; oblicz rozmiar pliku dołączonego do sektora rozruchowego
			dw	0x0000		; przesunięcie
			dw	STATIC_ZERO_kernel_address	; segment
			dq	0x0000000000000001	; adres LBA pierwszego sektora dołączonego pliku

align 0x10	; wszystkie tablice trzymamy pod pełnym adresem
zero_table_gdt_32bit:
	; deskryptor zerowy
	dq	STATIC_EMPTY
	; deskryptor kodu
	dq	0000000011001111100110000000000000000000000000001111111111111111b
	; deskryptor danych
	dq	0000000011001111100100100000000000000000000000001111111111111111b
zero_table_gdt_32bit_end:

zero_header_gdt_32bit:
	dw	zero_table_gdt_32bit_end - zero_table_gdt_32bit - 0x01
	dd	zero_table_gdt_32bit

;-------------------------------------------------------------------------------
; uzupełniamy niewykorzystaną przestrzeń po samą tablicę partycji
times	436 - ( $ - $$ )		db	0x00

;-------------------------------------------------------------------------------
; identyfikator nośnika
;-------------------------------------------------------------------------------
		db	0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00

;-------------------------------------------------------------------------------
; partycja podstawowa 0
;-------------------------------------------------------------------------------
		db	0x00	; brak sektora rozruchowego na partycji
		db	0x00, 0x00, 0x00	; CHS
		db	0xEB	; id partycji, nie ma znaczenia
		db	0x00, 0x00, 0x00	; CHS
		dd	(file_kernel_end - $$) / 512	; LBA partycji
		dd	(1048576 - (file_kernel_end - $$)) / 512	; rozmiar partycji w sektorach

;-------------------------------------------------------------------------------
; znacznik sektora rozruchowego
times	510 - ($ - $$)		db	STATIC_EMPTY
				dw	STATIC_ZERO_magic	; czysta magija ;>

file_kernel:
	;-----------------------------------------------------------------------
	; dołącz plik jądra systemu
	;-----------------------------------------------------------------------
	incbin	"build/kernel"
	align	STATIC_SECTOR_SIZE_byte	; wyrównaj kod do pełnego sektora o rozmiarze 512 Bajtów
file_kernel_end:

;-------------------------------------------------------------------------------
; wyrównaj obraz dysku do pełnego 1 MiB
times	1048576 - ($ - $$)	db	STATIC_EMPTY
