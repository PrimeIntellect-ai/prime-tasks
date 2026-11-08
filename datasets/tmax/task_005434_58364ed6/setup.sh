#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc zip tar binutils

pip3 install pytest

mkdir -p /app
cat << 'EOF' > /app/emitter.c
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <string.h>
#include <time.h>
#include <sys/stat.h>

int main() {
    mkdir("/home/user/dropzone", 0777);
    srand(time(NULL) ^ getpid());
    char cmd[512];
    char tmpdir[256];
    sprintf(tmpdir, "/tmp/emitter_%d", getpid());
    mkdir(tmpdir, 0777);
    chdir(tmpdir);

    while(1) {
        int r = rand();
        long t = (long)time(NULL);

        FILE *f = fopen("event.log", "w");
        if (f) {
            fprintf(f, "LOG_LINE_%ld_%d\n", t, r);
            fclose(f);
        }

        system("tar -czf inner.tar.gz event.log >/dev/null 2>&1");

        char tmp_file[256];
        sprintf(tmp_file, "/home/user/dropzone/archive_%ld_%d.tmp", t, r);
        char zip_file[256];
        sprintf(zip_file, "/home/user/dropzone/archive_%ld_%d.zip", t, r);

        sprintf(cmd, "zip -q %s inner.tar.gz >/dev/null 2>&1", tmp_file);
        system(cmd);

        rename(tmp_file, zip_file);

        usleep(40000);
    }
    return 0;
}
EOF

gcc -O3 /app/emitter.c -o /app/log_emitter
strip /app/log_emitter
rm /app/emitter.c

useradd -m -s /bin/bash user || true
mkdir -p /home/user/dropzone
chmod -R 777 /home/user
