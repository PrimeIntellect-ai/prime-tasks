#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip wget build-essential autoconf automake libtool file
    pip3 install pytest

    mkdir -p /app/vendor /app/corpora/clean /app/corpora/evil

    # Download and extract inotify-tools
    wget https://github.com/inotify-tools/inotify-tools/archive/refs/tags/3.22.6.0.tar.gz -O /tmp/inotify.tar.gz
    tar -xzf /tmp/inotify.tar.gz -C /tmp/
    mv /tmp/inotify-tools-3.22.6.0 /app/vendor/inotify-tools-3.22.6
    rm /tmp/inotify.tar.gz

    # Perturb the source code
    sed -i 's/int main(/int mian(/g' /app/vendor/inotify-tools-3.22.6/src/inotifywait.c

    # Create corpora
    cat << 'EOF' > /tmp/clean1.txt
[Artifact: SafeApp]
Path: bin/app
Hash: 1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef
Description: A safe app

EOF

    cat << 'EOF' > /tmp/clean2.txt
[Artifact: SafeApp2]
Path: lib/libfoo.so
Hash: 1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef
Description: A safe lib

EOF

    cat << 'EOF' > /tmp/evil1.txt
[Artifact: EvilApp]
Path: /bin/app
Hash: 1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef
Description: Evil app - absolute path

EOF

    cat << 'EOF' > /tmp/evil2.txt
[Artifact: EvilApp2]
Path: bin/app
Hash: z234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef
Description: Evil app - bad hash

EOF

    cat << 'EOF' > /tmp/evil3.txt
[Artifact: EvilApp3$(rm -rf /)]
Path: bin/app
Hash: 1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef
Description: Evil app - injection

EOF

    cat << 'EOF' > /tmp/evil4.txt
[Artifact: EvilApp4]
Path: ../bin/app
Hash: 1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef
Description: Evil app - traversal

EOF

    iconv -f UTF-8 -t UTF-16LE /tmp/clean1.txt > /app/corpora/clean/1.manifest
    iconv -f UTF-8 -t WINDOWS-1252 /tmp/clean2.txt > /app/corpora/clean/2.manifest

    iconv -f UTF-8 -t UTF-16LE /tmp/evil1.txt > /app/corpora/evil/1.manifest
    iconv -f UTF-8 -t WINDOWS-1252 /tmp/evil2.txt > /app/corpora/evil/2.manifest
    iconv -f UTF-8 -t UTF-16LE /tmp/evil3.txt > /app/corpora/evil/3.manifest
    iconv -f UTF-8 -t WINDOWS-1252 /tmp/evil4.txt > /app/corpora/evil/4.manifest

    rm /tmp/clean1.txt /tmp/clean2.txt /tmp/evil1.txt /tmp/evil2.txt /tmp/evil3.txt /tmp/evil4.txt

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
