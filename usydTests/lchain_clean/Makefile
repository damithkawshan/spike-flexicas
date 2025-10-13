# Makefile for lchain_clean - RISC-V build for Spike

# RISC-V toolchain
CC = riscv64-unknown-elf-gcc
CFLAGS = -Wall -Wextra -O2 -g -static
LDFLAGS = -static

TARGET = lchain
SRC = lchain.c
OBJ = $(SRC:.c=.o)

.PHONY: all clean run spike

all: $(TARGET)

$(TARGET): $(OBJ)
	$(CC) $(CFLAGS) -o $@ $^ $(LDFLAGS)

%.o: %.c minimap.h ksort.h
	$(CC) $(CFLAGS) -c $< -o $@

clean:
	rm -f $(OBJ) $(TARGET)

run: $(TARGET)
	./$(TARGET)

spike: $(TARGET)
	spike pk $(TARGET)
