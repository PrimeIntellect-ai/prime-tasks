#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils zip
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/dataset
    mkdir -p /home/user/clean
    mkdir -p /app

    # Create verifier
    cat << 'EOF' > /app/verifier.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <elf.h>

int main(int argc, char **argv) {
    if (argc < 2) return 1;
    FILE *f = fopen(argv[1], "rb");
    if (!f) return 1;

    Elf64_Ehdr ehdr;
    if (fread(&ehdr, 1, sizeof(ehdr), f) != sizeof(ehdr)) { fclose(f); return 1; }
    if (memcmp(ehdr.e_ident, ELFMAG, SELFMAG) != 0 || ehdr.e_ident[EI_CLASS] != ELFCLASS64) {
        fclose(f); return 1;
    }

    fseek(f, ehdr.e_shoff, SEEK_SET);
    Elf64_Shdr *shdrs = malloc(ehdr.e_shnum * sizeof(Elf64_Shdr));
    if (fread(shdrs, sizeof(Elf64_Shdr), ehdr.e_shnum, f) != ehdr.e_shnum) {
        free(shdrs); fclose(f); return 1;
    }

    char *shstrtab = NULL;
    if (ehdr.e_shstrndx != SHN_UNDEF) {
        Elf64_Shdr *shstr_shdr = &shdrs[ehdr.e_shstrndx];
        shstrtab = malloc(shstr_shdr->sh_size);
        fseek(f, shstr_shdr->sh_offset, SEEK_SET);
        if (fread(shstrtab, 1, shstr_shdr->sh_size, f) != shstr_shdr->sh_size) {
            free(shstrtab); free(shdrs); fclose(f); return 1;
        }
    }

    int ret = 1;
    for (int i = 0; i < ehdr.e_shnum; i++) {
        if (shstrtab && strcmp(shstrtab + shdrs[i].sh_name, ".research_data") == 0) {
            fseek(f, shdrs[i].sh_offset, SEEK_SET);
            unsigned int magic = 0;
            if (fread(&magic, 1, sizeof(magic), f) == sizeof(magic)) {
                if (magic == 0x1337BEEF) {
                    ret = 0;
                }
            }
            break;
        }
    }

    free(shdrs);
    if (shstrtab) free(shstrtab);
    fclose(f);
    return ret;
}
EOF

    gcc -O2 -s /app/verifier.c -o /app/dataset_verifier
    rm /app/verifier.c

    # Generate dataset
    cat << 'EOF' > /tmp/gen.py
import os
import random
import subprocess
import shutil

os.makedirs("/home/user/dataset", exist_ok=True)
os.makedirs("/home/user/clean", exist_ok=True)

with open("/tmp/dummy.c", "w") as f:
    f.write("int main() { return 0; }")
subprocess.run(["gcc", "/tmp/dummy.c", "-o", "/tmp/dummy.elf"])

with open("/tmp/data.bin", "wb") as f:
    f.write(b"\xef\xbe\x37\x13")

subprocess.run(["objcopy", "--add-section", ".research_data=/tmp/data.bin", "/tmp/dummy.elf", "/tmp/valid.elf"])

num_files = 10000
num_valid = 500
valid_indices = set(random.sample(range(num_files), num_valid))

for i in range(num_files):
    subdir = f"/home/user/dataset/dir_{i % 50}"
    os.makedirs(subdir, exist_ok=True)
    src = "/tmp/valid.elf" if i in valid_indices else "/tmp/dummy.elf"
    dst = f"{subdir}/file_{i}.elf"
    shutil.copy(src, dst)

for i in range(20):
    d1 = f"/home/user/dataset/dir_{i % 50}"
    d2 = f"/home/user/dataset/dir_{(i + 1) % 50}"
    try:
        os.symlink(d2, f"{d1}/loop_{i}")
    except FileExistsError:
        pass
EOF

    python3 /tmp/gen.py
    rm -rf /tmp/dummy.c /tmp/dummy.elf /tmp/data.bin /tmp/valid.elf /tmp/gen.py

    chmod -R 777 /home/user
