#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc strace ltrace bc
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/suspicious.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

int main() {
    FILE *f = fopen("/home/user/input.txt", "r");
    if (!f) {
        printf("Missing input.txt\n");
        return 1;
    }

    char line[256];
    double sum = 0.0;
    while (fgets(line, sizeof(line), f)) {
        if (strncmp(line, "DATA:", 5) != 0) {
            printf("Format error\n");
            fclose(f);
            return 1;
        }
        double val = atof(line + 5);
        sum += val;
    }
    fclose(f);

    // Tracing hint
    char logname[256];
    sprintf(logname, "/tmp/sum_%.6f.log", sum);
    FILE *log = fopen(logname, "w");
    if (log) {
        fprintf(log, "checked\n");
        fclose(log);
    }

    // Target sum is 8.888888
    if (fabs(sum - 8.888888) < 0.000001) {
        FILE *flag = fopen("/home/user/flag.txt", "w");
        if (flag) {
            fprintf(flag, "PAYLOAD_UNLOCKED_77492\n");
            fclose(flag);
        }
    } else {
        printf("Sum is incorrect.\n");
    }
    return 0;
}
EOF

    gcc -o /home/user/suspicious /home/user/suspicious.c -lm
    rm /home/user/suspicious.c

    cat << 'EOF' > /home/user/generate.sh
#!/bin/bash
# Generates test coordinates
rm -f /home/user/input.txt

# Bug: Space after colon causes format error in strict parser
echo "DATA: 1.111111" >> /home/user/input.txt
echo "DATA: 2.222222" >> /home/user/input.txt
EOF
    chmod +x /home/user/generate.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
