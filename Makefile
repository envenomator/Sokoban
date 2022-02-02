ALL_ASM = $(wildcard *.asm) $(wildcard *.inc)

all: $(ALL_ASM)
	cl65 -C cerberus.cfg -o SOKOBAN.PRG -l sokoban.list sokoban.asm
clean:
	rm -f *.PRG *.list *.o
