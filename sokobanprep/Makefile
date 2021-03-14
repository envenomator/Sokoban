CC=gcc
CFLAGS=-I.

%.o: %.c $(DEPS)
	$(CC) -c -o $@ $< $(CFLAGS)

sokobanprep: sokobanprep.c
	$(CC) -o sokobanprep sokobanprep.c
