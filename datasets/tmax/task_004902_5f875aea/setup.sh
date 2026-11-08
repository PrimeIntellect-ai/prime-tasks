#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc binutils
pip3 install pytest pandas numpy

mkdir -p /app /home/user

cat << 'EOF' > /app/extractor.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main() {
    char line[256];
    int count = 0;
    char buffer[4][256];
    int buf_len = 0;

    if (fgets(line, sizeof(line), stdin)) {
        printf("id,timestamp,category,extracted_value\n");
    }

    while (fgets(line, sizeof(line), stdin)) {
        char id[64], ts[64], cat[64];
        float val;
        sscanf(line, "%[^,],%[^,],%[^,],%f", id, ts, cat, &val);

        char out_line[256];
        sprintf(out_line, "%s,%s,%s,%.2f\n", id, ts, cat, val * 1.5);

        strcpy(buffer[buf_len++], out_line);
        count++;

        if (count % 3 == 0) {
            strcpy(buffer[buf_len++], out_line); // inject duplicate
        }

        if (buf_len >= 4) {
            for(int i = buf_len - 1; i >= 0; i--) {
                printf("%s", buffer[i]);
            }
            buf_len = 0;
        }
    }
    for(int i = buf_len - 1; i >= 0; i--) {
        printf("%s", buffer[i]);
    }
    return 0;
}
EOF
gcc -O2 /app/extractor.c -o /app/feature_extractor
strip /app/feature_extractor
rm /app/extractor.c

cat << 'EOF' > /home/user/events.csv
id,timestamp,category,raw_value
1,1620000000,A,10.0
2,1620000010,B,20.0
3,1620000020,A,30.0
4,1620000030,C,15.0
5,1620000040,B,25.0
6,1620000050,A,5.0
7,1620000060,C,12.0
8,1620000070,B,8.0
EOF

useradd -m -s /bin/bash user || true
chown -R user:user /home/user
chmod -R 777 /home/user
