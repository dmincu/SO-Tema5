.PHONY: build clean

CC=gcc
CFLAGS=-Wall -g
INCLUDE=-I.

build: aws

aws: src/server.c
	$(CC) $(CFLAGS) $(INCLUDE) -o $@ $^

clean:
	rm -rf *.o aws
