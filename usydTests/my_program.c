#include <stdio.h>

#define FLEXICAS_CSR 0x8F0

// CSR read/write macros
#define csr_write(csr, val) \
    asm volatile ("csrw " #csr ", %0" :: "r"(val))
    
#define csr_read(csr) ({ \
    unsigned long __tmp; \
    asm volatile ("csrr %0, " #csr : "=r"(__tmp)); \
    __tmp; })

// Flexicas commands
#define FLEXICAS_START         0x8000000000000000ull
#define FLEXICAS_STOP          0x8000000000000001ull
#define FLEXICAS_QUERY(addr)   (0x9000000000000000ull | ((unsigned long)(addr) & 0x00ffffffffffffffull))
#define FLEXICAS_FLUSH(addr)   (0x8200000000000000ull | ((unsigned long)(addr) & 0x00ffffffffffffffull))

int main() {
    int data[1000];
    
    // Start performance counter logging
    csr_write(0x8F0, FLEXICAS_START);
    
    // Your code here
    for(int i = 0; i < 1000; i++) {
        data[i] = i * 2;
    }
    
    // Query if an address is in cache
    unsigned long result = 0;
    csr_write(0x8F0, FLEXICAS_QUERY(&data[0]));
    result = csr_read(0x8F0);
    printf("Cache query result: %lu\n", result);
    
    printf("Hello World!\n");

    // Stop performance counter logging
    csr_write(0x8F0, FLEXICAS_STOP);
    return 0;
}