ENTRY(_start)
MEMORY { ROM (rx) : ORIGIN = 0, LENGTH = 40K
         RAM (rwx) : ORIGIN = 0x10000000, LENGTH = 24K }
SECTIONS {
 .text : { KEEP(*(.text.start)) *(.text*) *(.rodata*) . = ALIGN(4); } > ROM
 .data : { . = ALIGN(4); __data_start = .; *(.sdata*) *(.data*) . = ALIGN(4); __data_end = .; } > RAM AT > ROM
 __data_load = LOADADDR(.data);
 .bss (NOLOAD): { . = ALIGN(8); __bss_start = .; *(.sbss*) *(.bss*) *(COMMON) . = ALIGN(8); __bss_end = .; } > RAM
 __global_pointer$ = __data_start + 0x800;
 __stack_top = ORIGIN(RAM) + LENGTH(RAM);
 ASSERT(__bss_end+6144<=__stack_top,"Data/heap leaves less than 6KB stack")
 /DISCARD/ : { *(.comment*) *(.eh_frame*) }
}
