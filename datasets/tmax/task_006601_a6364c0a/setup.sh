#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc
pip3 install pytest

useradd -m -s /bin/bash user || true

mkdir -p /home/user/pipeline/data
mkdir -p /home/user/pipeline/lib_legacy
mkdir -p /home/user/pipeline/lib_modern

cat << 'EOF' > /home/user/pipeline/log_parser.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char *argv[]) {
    char* lib_path = getenv("LD_LIBRARY_PATH");
    if (lib_path != NULL && strstr(lib_path, "lib_legacy") != NULL) {
        fprintf(stderr, "log_parser: symbol lookup error: undefined symbol: parse_v2 (found legacy libutils.so)\n");
        return 1;
    }

    if (argc < 2) return 1;

    FILE *f = fopen(argv[1], "r");
    if (!f) return 1;

    char line[256];
    while (fgets(line, sizeof(line), f)) {
        if (strstr(line, "FATAL_CORRUPTION") != NULL) {
            fprintf(stderr, "Segmentation fault (core dumped)\n");
            fprintf(stderr, "#0 0x00007ffff7a3b000 in parse_line () from libutils.so\n");
            fprintf(stderr, "#1 0x0000555555554000 in main () at log_parser.c:45\n");
            exit(139);
        }
        line[strcspn(line, "\n")] = 0;
        printf("PROCESSED: %s\n", line);
    }
    fclose(f);
    return 0;
}
EOF

gcc /home/user/pipeline/log_parser.c -o /home/user/pipeline/log_parser

touch /home/user/pipeline/lib_legacy/libutils.so
touch /home/user/pipeline/lib_modern/libutils.so

for i in 1 2 3 4 5; do
    echo "Data line A for file $i" > /home/user/pipeline/data/file_$i.log
    echo "Data line B for file $i" >> /home/user/pipeline/data/file_$i.log
done

echo "Data line A for file 6" > /home/user/pipeline/data/file_6.log
echo "FATAL_CORRUPTION" >> /home/user/pipeline/data/file_6.log
echo "Data line C for file 6" >> /home/user/pipeline/data/file_6.log

cat << 'EOF' > /home/user/pipeline/run_pipeline.sh
#!/bin/bash
export LD_LIBRARY_PATH=/home/user/pipeline/lib_legacy:$LD_LIBRARY_PATH

rm -f /home/user/pipeline/output.txt
for file in /home/user/pipeline/data/*.log; do
    /home/user/pipeline/log_parser "$file" >> /home/user/pipeline/output.txt &
done
wait
EOF
chmod +x /home/user/pipeline/run_pipeline.sh

chown -R user:user /home/user/pipeline
chmod -R 777 /home/user
