ENTRY(_start)
MEMORY { FLASH (rx) : ORIGIN  =  0, LENGTH  =  448K
         RAM (rwx) : ORIGIN  =  0x20000000, LENGTH  =  16K
         RAMX (rwx) : ORIGIN  =  0x20020000, LENGTH  =  96K }
SECTIONS {
 .text : { KEEP(*(.init)) *(.text*) *(.rodata*) .  =  ALIGN(4); } > FLASH
 .data : { .  =  ALIGN(4); __data_start = .; *(.sdata*) *(.data*) .  =  ALIGN(4); __data_end = .; } > RAM AT > FLASH
 __data_load = LOADADDR(.data);
 .bss (NOLOAD) : { .  =  ALIGN(8); __bss_start = .; *(.sbss*) *(.bss*) *(COMMON) .  =  ALIGN(8); __bss_end = .; } > RAM
 .DMADATA (NOLOAD) : { .  =  ALIGN(16); *(.DMADATA*) *(.dmadata*) } > RAMX
 __global_pointer$ = __data_start+0x800;
 __stack_top = ORIGIN(RAM)+LENGTH(RAM);
 ASSERT(__bss_end+4096<=__stack_top,"CH569 stack reserve below4KiB")
 /DISCARD/ : { *(.comment*) *(.eh_frame*) }
}
