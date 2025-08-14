
all: zx0 dzx0

zx0: zx0.c optimize.c compress.c memory.c zx0.h
	gcc -o zx0 zx0.c optimize.c compress.c memory.c

dzx0: dzx0.c
	gcc -o dzx0 dzx0.c

clean:
	rm -f zx0 dzx0
