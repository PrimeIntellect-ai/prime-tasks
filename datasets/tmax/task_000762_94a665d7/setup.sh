#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc binutils tar gzip
pip3 install pytest

useradd -m -s /bin/bash user || true

mkdir -p /home/user/archives
mkdir -p /home/user/extracted

# Helper to create a dummy C file, compile it, and package it
create_archive() {
    local name=$1
    local title=$2
    local corrupt=$3

    local tmpdir=$(mktemp -d)
    echo "$title" > "$tmpdir/readme.md"
    echo "This is some dummy documentation text for $name." >> "$tmpdir/readme.md"

    echo "int main() { return 0; }" > "$tmpdir/app.c"
    gcc "$tmpdir/app.c" -o "$tmpdir/app.bin"
    rm "$tmpdir/app.c"

    if [ "$corrupt" = "true" ]; then
        # Create a valid tar, then gzip it, then truncate it to simulate corruption
        tar -cvf "$tmpdir/dummy.tar" -C "$tmpdir" readme.md app.bin > /dev/null 2>&1
        gzip "$tmpdir/dummy.tar"
        head -c 150 "$tmpdir/dummy.tar.gz" > "/home/user/archives/$name.tar.gz"
    else
        tar -czvf "/home/user/archives/$name.tar.gz" -C "$tmpdir" readme.md app.bin > /dev/null 2>&1
    fi
    rm -rf "$tmpdir"
}

# Create valid archives
create_archive "arch_alpha" "# Core Engine" "false"
create_archive "arch_beta" "# UI Framework" "false"
create_archive "arch_gamma" "# Networking Stack" "false"

# Create corrupt archives
create_archive "arch_delta" "# Data Pipeline" "true"
create_archive "arch_epsilon" "# Auth Module" "true"

chown -R user:user /home/user/archives
chown -R user:user /home/user/extracted

chmod -R 777 /home/user
