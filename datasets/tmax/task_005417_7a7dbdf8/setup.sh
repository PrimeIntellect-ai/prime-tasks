#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc binutils strace ltrace gdb xxd
pip3 install pytest

mkdir -p /app
cat << 'EOF' > /tmp/oracle.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <elf.h>
#include <fcntl.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <unistd.h>
#include <iconv.h>

int main(int argc, char **argv) {
    if (argc != 2) return 1;
    int fd = open(argv[1], O_RDONLY);
    if (fd < 0) return 1;
    struct stat st;
    if (fstat(fd, &st) < 0) return 1;
    if (st.st_size < sizeof(Elf64_Ehdr)) return 1;
    void *map = mmap(NULL, st.st_size, PROT_READ, MAP_PRIVATE, fd, 0);
    if (map == MAP_FAILED) return 1;

    Elf64_Ehdr *ehdr = (Elf64_Ehdr *)map;
    if (memcmp(ehdr->e_ident, ELFMAG, SELFMAG) != 0) return 1;

    Elf64_Shdr *shdrs = (Elf64_Shdr *)((uint8_t *)map + ehdr->e_shoff);
    Elf64_Shdr *strtab = &shdrs[ehdr->e_shstrndx];
    const char *strtab_p = (const char *)map + strtab->sh_offset;

    for (int i = 0; i < ehdr->e_shnum; i++) {
        const char *name = strtab_p + shdrs[i].sh_name;
        if (strcmp(name, ".pkg_meta") == 0) {
            size_t size = shdrs[i].sh_size;
            uint8_t *data = (uint8_t *)map + shdrs[i].sh_offset;
            uint8_t *dec = malloc(size);
            for (size_t j = 0; j < size; j++) dec[j] = data[j] ^ 0x5A;

            iconv_t cd = iconv_open("UTF-8", "UTF-16LE");
            if (cd == (iconv_t)-1) {
                fwrite(dec, 1, size, stdout);
                printf("\n");
                return 0;
            }
            size_t inbytes = size;
            size_t outbytes = size * 4 + 1;
            char *outbuf = calloc(1, outbytes);
            char *inptr = (char *)dec;
            char *outptr = outbuf;
            iconv(cd, &inptr, &inbytes, &outptr, &outbytes);
            iconv_close(cd);

            size_t final_size = outptr - outbuf;
            fwrite(outbuf, 1, final_size, stdout);
            printf("\n");
            return 0;
        }
    }
    printf("NO_META\n");
    return 1;
}
EOF

gcc -O2 /tmp/oracle.c -o /app/legacy_extractor
strip /app/legacy_extractor
chmod +x /app/legacy_extractor
rm /tmp/oracle.c

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
