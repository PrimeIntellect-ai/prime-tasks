#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip git gcc make imagemagick tesseract-ocr fonts-dejavu-core
pip3 install pytest

mkdir -p /app
convert -size 600x150 xc:white -font DejaVu-Sans -pointsize 24 -fill black -draw "text 10,40 'FATAL_OFFSET:0x1A4F\nTRACE: thread_worker -> extract_dump'" /app/bug_report.png

useradd -m -s /bin/bash user || true
mkdir -p /home/user/telemetry_repo
cd /home/user/telemetry_repo
git init
git config user.email "dev@local"
git config user.name "Dev"

cat << 'EOF' > telemetry.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <pthread.h>

char buffer[1024];
pthread_mutex_t buffer_lock = PTHREAD_MUTEX_INITIALIZER;

void* thread_worker(void* arg) {
    char* input = (char*)arg;
    pthread_mutex_lock(&buffer_lock);
    strncpy(buffer, input, sizeof(buffer)-1);
    buffer[sizeof(buffer)-1] = '\0';
    pthread_mutex_unlock(&buffer_lock);
    return NULL;
}

int main(int argc, char** argv) {
    if (argc < 2) return 1;
    pthread_t t1;
    pthread_create(&t1, NULL, thread_worker, argv[1]);
    pthread_join(t1, NULL);
    printf("%s\n", buffer);
    return 0;
}
EOF

cat << 'EOF' > Makefile
all:
	gcc -o telemetry telemetry.c -lpthread
EOF

git add telemetry.c Makefile
git commit -m "Commit 1"

for i in $(seq 2 149); do
    echo "// commit $i" >> telemetry.c
    git commit -am "Commit $i"
done

make
cp telemetry /app/oracle_parser
strip /app/oracle_parser

cat << 'EOF' > telemetry.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <pthread.h>

char buffer[1024];
pthread_mutex_t buffer_lock = PTHREAD_MUTEX_INITIALIZER;

void* thread_worker(void* arg) {
    char* input = (char*)arg;
    strncpy(buffer, input, sizeof(buffer)-1);
    buffer[sizeof(buffer)-1] = '\0';
    return NULL;
}

int main(int argc, char** argv) {
    if (argc < 2) return 1;
    pthread_t t1;
    pthread_create(&t1, NULL, thread_worker, argv[1]);
    pthread_join(t1, NULL);
    printf("%s\n", buffer);
    return 0;
}
EOF

cat << 'EOF' > Makefile
all:
	gcc -o telemetry telemetry.c
EOF

echo "// commit 150" >> telemetry.c
git commit -am "Commit 150"

for i in $(seq 151 200); do
    echo "// commit $i" >> telemetry.c
    git commit -am "Commit $i"
done

chown -R user:user /home/user/telemetry_repo
chmod -R 777 /home/user
chmod -R 777 /app
