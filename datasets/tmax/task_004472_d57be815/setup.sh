#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils
    pip3 install pytest

    mkdir -p /app/corpora/clean
    mkdir -p /app/corpora/evil

    # Create the analyzer binary
    cat << 'EOF' > /tmp/analyzer.c
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char *argv[]) {
    if (argc < 2) return 1;
    FILE *f = fopen(argv[1], "rb");
    if (!f) return 1;
    printf("Analyzed: %s\n", argv[1]);
    fclose(f);
    return 0;
}
EOF
    gcc -static -O2 -o /app/analyzer /tmp/analyzer.c
    strip /app/analyzer
    chmod +x /app/analyzer
    rm /tmp/analyzer.c

    # Populate clean corpus
    echo "test1" > /app/corpora/clean/file1.txt
    echo "test2" > /app/corpora/clean/file2.txt
    ln -s file1.txt /app/corpora/clean/sym1.txt
    mkdir /app/corpora/clean/dir1
    echo "test3" > /app/corpora/clean/dir1/file3.txt
    ln -s dir1 /app/corpora/clean/symdir
    ln -s sym1.txt /app/corpora/clean/nested_sym.txt

    # Populate evil corpus
    ln -s self.txt /app/corpora/evil/self.txt
    ln -s b.txt /app/corpora/evil/a.txt
    ln -s a.txt /app/corpora/evil/b.txt
    mkdir /app/corpora/evil/dir2
    ln -s dir2/c.txt /app/corpora/evil/deep_a.txt
    ln -s ../deep_a.txt /app/corpora/evil/dir2/c.txt

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
