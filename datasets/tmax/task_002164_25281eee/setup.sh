#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc make wget cron
pip3 install pytest

mkdir -p /app
mkdir -p /home/user/incoming
mkdir -p /home/user/processed

# Download and setup libcsv-3.0.3
cd /app
wget https://sourceforge.net/projects/libcsv/files/libcsv/libcsv-3.0.3/libcsv-3.0.3.tar.gz
tar xf libcsv-3.0.3.tar.gz
rm libcsv-3.0.3.tar.gz
cd libcsv-3.0.3
./configure
sed -i 's/^CC = .*/CC = gccc/' Makefile
sed -i 's/^prefix = .*/prefix = \/usr\/local/' Makefile

# Create oracle_imputer
cat << 'EOF' > /app/oracle_imputer.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct {
    long long ts;
    double val;
    int is_nan;
} Row;

int main(int argc, char **argv) {
    if(argc < 2) return 1;
    FILE *f = fopen(argv[1], "r");
    if(!f) return 1;

    int cap = 1000;
    Row *rows = malloc(cap * sizeof(Row));
    int n = 0;

    char line[1024];
    while(fgets(line, sizeof(line), f)) {
        if(n == cap) { cap *= 2; rows = realloc(rows, cap * sizeof(Row)); }
        char *comma = strchr(line, ',');
        if(!comma) continue;
        *comma = 0;
        rows[n].ts = atoll(line);
        char *vstr = comma + 1;
        while(*vstr == ' ' || *vstr == '\t') vstr++;
        if(vstr[0] == '\n' || vstr[0] == '\r' || vstr[0] == 0 || strncmp(vstr, "NaN", 3) == 0) {
            rows[n].is_nan = 1;
            rows[n].val = 0;
        } else {
            rows[n].is_nan = 0;
            rows[n].val = atof(vstr);
        }
        n++;
    }
    fclose(f);

    for(int i=0; i<n; i++) {
        if(rows[i].is_nan) {
            int prev = -1, next = -1;
            for(int j=i-1; j>=0; j--) { if(!rows[j].is_nan) { prev = j; break; } }
            for(int j=i+1; j<n; j++) { if(!rows[j].is_nan) { next = j; break; } }

            if(prev != -1 && next != -1) {
                double t = (double)(rows[i].ts - rows[prev].ts) / (rows[next].ts - rows[prev].ts);
                rows[i].val = rows[prev].val + t * (rows[next].val - rows[prev].val);
            } else if(prev != -1) {
                rows[i].val = rows[prev].val;
            } else if(next != -1) {
                rows[i].val = rows[next].val;
            } else {
                rows[i].val = 0.0;
            }
        }
    }

    for(int i=0; i<n; i++) {
        printf("%lld,%.6f\n", rows[i].ts, rows[i].val);
    }
    free(rows);
    return 0;
}
EOF

gcc -O3 /app/oracle_imputer.c -o /app/oracle_imputer
chmod +x /app/oracle_imputer

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
