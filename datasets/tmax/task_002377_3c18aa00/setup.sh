#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils
    pip3 install pytest

    # Create dummy doc_compiler
    mkdir -p /app
    cat << 'EOF' > /tmp/doc_compiler.c
#include <stdio.h>
const char* backdoor = "__OVERRIDE_DOC_ROOT_PRIVILEGE__";
int main() {
    printf("Doc Compiler\n");
    return 0;
}
EOF
    gcc -O2 -s /tmp/doc_compiler.c -o /app/doc_compiler
    rm /tmp/doc_compiler.c

    # Create corpus directories
    mkdir -p /app/corpus/clean
    mkdir -p /app/corpus/evil

    # Generate tar files using Python
    cat << 'EOF' > /tmp/gen_corpus.py
import tarfile
import os

# Clean archives
for i in range(1, 6):
    filename = f'clean_{i}.md'
    with open(filename, 'w') as f:
        f.write(f'This is a clean markdown file {i}.\n')
    with tarfile.open(f'/app/corpus/clean/clean_{i}.tar.gz', 'w:gz') as tar:
        tar.add(filename)
    os.remove(filename)

# Evil 1: Path traversal
with tarfile.open('/app/corpus/evil/evil_1.tar.gz', 'w:gz') as tar:
    info = tarfile.TarInfo(name='../../../etc/passwd')
    info.size = 12
    with open('/tmp/dummy', 'wb') as f:
        f.write(b'dummy content')
    with open('/tmp/dummy', 'rb') as f:
        tar.addfile(info, f)

# Evil 2: Absolute path
with tarfile.open('/app/corpus/evil/evil_2.tar.gz', 'w:gz') as tar:
    info = tarfile.TarInfo(name='/var/www/html/index.html')
    info.size = 12
    with open('/tmp/dummy', 'rb') as f:
        tar.addfile(info, f)

# Evil 3: Backdoor string
with open('evil_3.md', 'w') as f:
    f.write('Metadata:\n__OVERRIDE_DOC_ROOT_PRIVILEGE__\n\nContent here.')
with tarfile.open('/app/corpus/evil/evil_3.tar.gz', 'w:gz') as tar:
    tar.add('evil_3.md')
os.remove('evil_3.md')

# Evil 4: Symlink
with tarfile.open('/app/corpus/evil/evil_4.tar.gz', 'w:gz') as tar:
    info = tarfile.TarInfo(name='link_out')
    info.type = tarfile.SYMTYPE
    info.linkname = '/etc'
    tar.addfile(info)

os.remove('/tmp/dummy')
EOF

    python3 /tmp/gen_corpus.py
    rm /tmp/gen_corpus.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
