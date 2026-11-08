#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc sqlite3
pip3 install pytest

useradd -m -s /bin/bash user || true

mkdir -p /home/user/project/bin
mkdir -p /home/user/project/assets
mkdir -p /home/user/project/out
mkdir -p /home/user/project/logs

cat << 'EOF' > /home/user/project/asset_compiler.c
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char *argv[]) {
    if(argc != 3) { 
        printf("FATAL: Invalid arguments.\n"); 
        return 1; 
    }
    FILE *f = fopen(argv[1], "r");
    if(!f) { 
        printf("ERR_FILE_NOT_FOUND: %s\n", argv[1]); 
        return 42; 
    }
    fclose(f);
    FILE *out = fopen(argv[2], "w");
    if(!out) return 1;
    fprintf(out, "COMPILED ASSET MAGIC\n");
    fclose(out);
    return 0;
}
EOF
gcc /home/user/project/asset_compiler.c -o /home/user/project/bin/asset_compiler
rm /home/user/project/asset_compiler.c

touch "/home/user/project/assets/logo.png"
touch "/home/user/project/assets/ui background.png"
touch "/home/user/project/assets/hero image.jpg"
touch "/home/user/project/assets/icon.png"

sqlite3 /home/user/project/assets.db << 'EOF'
CREATE TABLE assets (id INTEGER PRIMARY KEY, filename TEXT, active INTEGER);
INSERT INTO assets (filename, active) VALUES ('logo.png', 1);
INSERT INTO assets (filename, active) VALUES ('ui background.png', 1);
INSERT INTO assets (filename, active) VALUES ('hero image.jpg', 0);
INSERT INTO assets (filename, active) VALUES ('icon.png', 1);
EOF

cat << 'EOF' > /home/user/project/build.sh
#!/bin/bash
cd /home/user/project
rm -rf out/* logs/*

# Bug: splits by space in bash for-loop
ASSETS=$(sqlite3 assets.db "SELECT filename FROM assets WHERE active=1;")

for f in $ASSETS; do
    ./bin/asset_compiler "assets/$f" "out/$f.out" > logs/worker_${RANDOM}.log 2>&1 &
done
wait
EOF
chmod +x /home/user/project/build.sh

chown -R user:user /home/user/project
chmod -R 777 /home/user
