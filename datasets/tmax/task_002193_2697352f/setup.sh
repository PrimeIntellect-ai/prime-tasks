#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip bsdiff gcc
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /app/bsdiff_helper.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char *argv[]) {
    if (argc == 4) {
        char cmd[1024];
        snprintf(cmd, sizeof(cmd), "bsdiff \"%s\" \"%s\" \"%s\"", argv[1], argv[2], argv[3]);
        return system(cmd);
    } else if (argc == 5 && strcmp(argv[1], "-d") == 0) {
        char cmd[1024];
        snprintf(cmd, sizeof(cmd), "bspatch \"%s\" \"%s\" \"%s\"", argv[2], argv[4], argv[3]);
        return system(cmd);
    }
    printf("Usage: %s <old_file> <new_file> <patch_file>\n", argv[0]);
    printf("       %s -d <old_file> <patch_file> <new_file>\n", argv[0]);
    return 1;
}
EOF
    gcc -O2 -s -o /app/bsdiff_helper /app/bsdiff_helper.c
    rm /app/bsdiff_helper.c

    cat << 'EOF' > /tmp/generate_configs.py
import os, json, random, string
os.makedirs('/home/user/configs', exist_ok=True)
random.seed(42)
base_config = {f"key_{i}": "".join(random.choices(string.ascii_letters, k=50)) for i in range(1000)}

for idx in range(1000):
    mod_config = base_config.copy()
    for _ in range(10):
        mod_config[f"key_{random.randint(0, 999)}"] = "".join(random.choices(string.ascii_letters, k=50))
    with open(f'/home/user/configs/config_{idx:04d}.json', 'w') as f:
        json.dump(mod_config, f, indent=2)
EOF
    python3 /tmp/generate_configs.py
    rm /tmp/generate_configs.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
