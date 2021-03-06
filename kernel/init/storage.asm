;===============================================================================
; Copyright (C) by Blackend.dev
;===============================================================================

;===============================================================================
kernel_init_storage:
	; sprawdź czy dostępny jest kontroler IDE
	mov	eax,	DRIVER_PCI_CLASS_SUBCLASS_ide
	call	driver_pci_find_class_and_subclass
	jc	.ide_end	; brak

	; inicjalizuj dostępne nośniki na kontrolerze IDE
	call	driver_ide_init

	; znaleziono jakiekolwiek nośniki danych?
	cmp	byte [driver_ide_devices_count],	STATIC_EMPTY
	je	.ide_end	; nie

	; wyświetl komunikat
	mov	ecx,	kernel_init_string_storage_ide_end - kernel_init_string_storage_ide
	mov	rsi,	kernel_init_string_storage_ide
	call	kernel_video_string

	; maksymalna ilość urządzeń IDE
	mov	cl,	0x04

	; ustaw wskaźnik na opis urządzenia
	mov	rsi,	kernel_init_string_storage_ide_hd

	; wyświetl wszystkie dostępne nośniki danych
	mov	rdi,	driver_ide_devices

.ide_loop:
	; wpis uzupełniony?
	cmp	word [rdi + DRIVER_IDE_STRUCTURE_DEVICE.channel],	STATIC_EMPTY
	je	.ide_next	; nie

	; zachowaj oryginalne rejestry
	push	rax
	push	rcx
	push	rsi
	push	rdi

	; pobierz rozmiar nośnika w Bajtach
	mov	rax,	qword [rdi + DRIVER_IDE_STRUCTURE_DEVICE.size_sectors]
	shl	rax,	STATIC_MULTIPLE_BY_512_shift	; zamień na Bajty

	; utwórz urządzenie blokowe w wirtualnym systemie plików
	mov	ecx,	kernel_init_string_storage_ide_hd_end - kernel_init_string_storage_ide_hd_path
	mov	rsi,	kernel_init_string_storage_ide_hd_path
	call	kernel_vfs_path_resolve
	mov	rbx,	qword [rsp]
	mov	dl,	KERNEL_VFS_FILE_TYPE_block_device
	call	kernel_vfs_file_touch

	; aktualizuj rozmiar urządzenia blokowego
	mov	qword [rdi + KERNEL_VFS_STRUCTURE_KNOT.size],	rax

	; wyświetl ścieżkę do urządzenia
	mov	ecx,	kernel_init_string_storage_ide_hd_end - kernel_init_string_storage_ide_hd
	mov	rsi,	kernel_init_string_storage_ide_hd
	call	kernel_video_string

	; wyświetl infomację o rozmiarze
	mov	ecx,	kernel_init_string_storage_ide_size_end - kernel_init_string_storage_ide_size
	mov	rsi,	kernel_init_string_storage_ide_size
	call	kernel_video_string

	; wyświetl rozmiar
	shr	rax,	STATIC_DIVIDE_BY_1024_shift	; zamień na KiB
	mov	ebx,	STATIC_NUMBER_SYSTEM_decimal
	xor	ecx,	ecx
	call	kernel_video_number

	; wyświetl format rozmiaru
	mov	ecx,	kernel_init_string_storage_ide_format_end - kernel_init_string_storage_ide_format
	mov	rsi,	kernel_init_string_storage_ide_format
	call	kernel_video_string

	; przywróć oryginalne rejestry
	pop	rdi
	pop	rsi
	pop	rcx
	pop	rax

.ide_next:
	; następna litera nośnika
	inc	byte [kernel_init_string_storage_ide_hd_letter]

	; przesuń wskaźnik na następny wpis
	add	rdi,	DRIVER_IDE_STRUCTURE_DEVICE.SIZE

	; koniec wpisów
	dec	cl
	jnz	.ide_loop	; nie

.ide_end:
