.PHONY: build clean

CC=gcc
CFLAGS=-Wall -g
LIBFLAGS=-laio
INCLUDE=-Isrc headers

build: aws

aws: src/server.c
	$(CC) $(CFLAGS) $(INCLUDE) $(LIBFLAGS) -o $@ $^

clean:
	rm -rf *.o aws
