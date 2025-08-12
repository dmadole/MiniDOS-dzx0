
all: dzx0.bin

lbr: dzx0.lbr

clean:
	rm -f dzx0.lst
	rm -f dzx0.bin
	rm -f dzx0.lbr

dzx0.bin: dzx0.asm include/bios.inc include/kernel.inc
	asm02 -L -b dzx0.asm
	rm -f dzx0.build

dzx0.lbr: dzx0.bin
	rm -f dzx0.lbr
	lbradd dzx0.lbr dzx0.bin

