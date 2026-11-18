#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip squashfs-tools gcc binutils
pip3 install pytest

mkdir -p /app
cat << 'EOF' > /app/patch_gen.c
#include <stdio.h>
#include <string.h>

int main(int argc, char **argv) {
    if(argc < 4) return 1;
    FILE *out = fopen(argv[3], "wb");
    if(!out) return 1;

    int optimize = 0;
    if(argc == 5 && strcmp(argv[4], "--lzma-pack") == 0) {
        optimize = 1;
    }

    if(optimize) {
        // Output small mock optimized data
        fprintf(out, "LZMA:OPT:12345");
    } else {
        // Output large unoptimized data
        for(int i=0; i<100; i++) {
            fprintf(out, "DIFF_METADATA_UNOPTIMIZED_PADDING_BLOCK_VERBOSE_OUTPUT_GENERATION_V1.0\n");
        }
    }
    fclose(out);
    return 0;
}
EOF

gcc -O2 /app/patch_gen.c -o /app/patch_gen
strip /app/patch_gen
rm /app/patch_gen.c

mkdir -p /home/user/new_configs
mkdir -p /home/user/old_configs

for i in $(seq 1 500); do
    if [ "$i" -le 100 ]; then
        echo "NEEDS_UPDATE=true" > /home/user/new_configs/config_$i.conf
        echo "API_KEY=secretxyz" >> /home/user/new_configs/config_$i.conf
        echo "DB_PASS=dbsecret" >> /home/user/new_configs/config_$i.conf

        echo "NEEDS_UPDATE=false" > /home/user/old_configs/config_$i.conf
        echo "API_KEY=oldsecret" >> /home/user/old_configs/config_$i.conf
        echo "DB_PASS=olddbsecret" >> /home/user/old_configs/config_$i.conf
    else
        echo "NEEDS_UPDATE=false" > /home/user/new_configs/config_$i.conf
        echo "API_KEY=secretxyz" >> /home/user/new_configs/config_$i.conf

        echo "NEEDS_UPDATE=false" > /home/user/old_configs/config_$i.conf
        echo "API_KEY=oldsecret" >> /home/user/old_configs/config_$i.conf
    fi
done

mksquashfs /home/user/old_configs /home/user/old_configs.sqsh
rm -rf /home/user/old_configs

mkdir -p /home/user/mnt_old

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
