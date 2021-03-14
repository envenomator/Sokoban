CC=gcc
CFLAGS=-I.
DEPS = loadstart.h
%.o: %.c $(DEPS)
	$(CC) -c -o $@ $< $(CFLAGS)

sokobanprep: sokobanprep.c
	$(CC) -o sokobanprep sokobanprep.c
