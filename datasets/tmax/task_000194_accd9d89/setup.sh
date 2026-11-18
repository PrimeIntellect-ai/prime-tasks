#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git strace gcc binutils gawk
    pip3 install pytest

    export GIT_AUTHOR_NAME="Test User"
    export GIT_AUTHOR_EMAIL="test@example.com"
    export GIT_COMMITTER_NAME="Test User"
    export GIT_COMMITTER_EMAIL="test@example.com"

    mkdir -p /home/user/image_processor
    cd /home/user/image_processor
    git init

    for i in $(seq 1 200); do
      export GIT_AUTHOR_DATE="2023-01-01 12:00:00 +0000"
      export GIT_COMMITTER_DATE="2023-01-01 12:00:00 +0000"

      cat <<EOF > main.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main() {
    int version = $i;
    if (version >= 142) {
        char mem_block[256] = "CONFIG_STR: outpUT_CORRUPT_X99.dat";
        FILE *dump = fopen("mem_dump.bin", "wb");
        if (dump) {
            fwrite(mem_block, 1, 256, dump);
            fclose(dump);
        }
        abort();
    } else {
        FILE *f = fopen("output.dat", "w");
        if (f) {
            fprintf(f, "data %d\n", version);
            fclose(f);
        }
    }
    return 0;
}
EOF

      git add main.c
      git commit -m "Commit $i"

      if [ "$i" -eq 1 ]; then
        git tag v1.0
      fi
      if [ "$i" -eq 200 ]; then
        git tag v2.0
      fi
    done

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
