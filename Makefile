ALL_ASM = $(wildcard *.asm) $(wildcard *.inc)

all: $(ALL_ASM)
	cl65 -t cx16 -o SOKOBAN.PRG -l sokoban.list sokoban.asm

clean:
	rm -f *.PRG *.list *.o
