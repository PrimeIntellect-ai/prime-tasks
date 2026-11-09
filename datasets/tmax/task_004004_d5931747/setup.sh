#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /app/core_engine.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

int main(int argc, char **argv) {
    if (argc < 2) return 1;
    FILE *f = fopen(argv[1], "r");
    if (!f) return 1;
    char buffer[4096];
    size_t n = fread(buffer, 1, sizeof(buffer)-1, f);
    buffer[n] = 0;
    fclose(f);

    char *ptr = strstr(buffer, "\"coordinates\"");
    if (!ptr) return 0;
    ptr = strchr(ptr, '[');
    if (!ptr) return 0;
    ptr++;

    float sum = 0;
    char *end;
    while (*ptr && *ptr != ']') {
        if (*ptr == ',' || *ptr == ' ' || *ptr == '\n' || *ptr == '\r' || *ptr == '"') {
            ptr++;
            continue;
        }
        double val = strtod(ptr, &end);
        if (ptr == end) {
            if (strncmp(ptr, "NaN", 3) == 0) {
                val = NAN;
                end = ptr + 3;
            } else if (strncmp(ptr, "Infinity", 8) == 0) {
                val = INFINITY;
                end = ptr + 8;
            } else {
                ptr++;
                continue;
            }
        }

        if (fabs(val) > 1e8 || isnan(val)) {
            int *p = NULL;
            *p = 0;
        }

        char *dot = strchr(ptr, '.');
        if (dot && dot < end) {
            int decimals = 0;
            for (char *c = dot + 1; c < end; c++) {
                if (*c >= '0' && *c <= '9') decimals++;
                else break;
            }
            if (decimals > 8) {
                int *p = NULL;
                *p = 0;
            }
        }

        sum += (float)val;
        ptr = end;
    }
    return 0;
}
EOF
    gcc -O2 -o /app/core_engine /app/core_engine.c -lm
    strip -s /app/core_engine
    rm /app/core_engine.c

    mkdir -p /home/user/legacy_pipeline
    cat << 'EOF' > /home/user/legacy_pipeline/build_helper.sh
#!/bin/bash
gcc -shared -o helper.so -fPIC helper.c
EOF
    chmod +x /home/user/legacy_pipeline/build_helper.sh

    cat << 'EOF' > /home/user/legacy_pipeline/helper.c
#include <math.h>

double compute(double a) {
    return sqrt(pow(a, 2.0));
}
EOF

    cat << 'EOF' > /home/user/legacy_pipeline/validator.py
import sys

if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit(0)
    sys.exit(0)
EOF

    cat << 'EOF' > /tmp/gen_corpus.py
import os
import json
import random

os.makedirs('/home/user/corpora/clean', exist_ok=True)
os.makedirs('/home/user/corpora/evil', exist_ok=True)

for i in range(50):
    with open(f'/home/user/corpora/clean/file_{i}.json', 'w') as f:
        json.dump({"coordinates": [round(random.uniform(-1000, 1000), 4) for _ in range(10)]}, f)

for i in range(50):
    with open(f'/home/user/corpora/evil/file_{i}.json', 'w') as f:
        choice = random.choice(['large', 'small', 'nan', 'inf', 'precision'])
        arr = [round(random.uniform(-1000, 1000), 4) for _ in range(9)]
        if choice == 'large':
            arr.append(round(random.uniform(1e8 + 1, 1e9), 2))
        elif choice == 'small':
            arr.append(round(random.uniform(-1e9, -1e8 - 1), 2))
        elif choice == 'nan':
            arr.append("NaN")
        elif choice == 'inf':
            arr.append("Infinity")

        s = '{"coordinates": [' + ', '.join(str(x) if not isinstance(x, str) else x for x in arr) + ']}'
        if choice == 'precision':
            s = '{"coordinates": [12.123456789]}'
        f.write(s)
EOF
    python3 /tmp/gen_corpus.py
    rm /tmp/gen_corpus.py

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
