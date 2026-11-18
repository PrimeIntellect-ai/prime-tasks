#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc make bc
pip3 install pytest

mkdir -p /app/lib-embed-tools/src
mkdir -p /app/lib-embed-tools/bin
mkdir -p /opt/oracle/bin

cat << 'EOF' > /app/lib-embed-tools/src/main.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

int main(int argc, char *argv[]) {
    if (argc != 3) {
        return 1;
    }
    char *a = argv[1];
    char *b = argv[2];

    double dot = 0.0, normA = 0.0, normB = 0.0;
    char *tokA = strtok(a, ":");
    char *tokB = strtok(b, ":");

    while (tokA != NULL && tokB != NULL) {
        double valA = atof(tokA);
        double valB = atof(tokB);
        dot += valA * valB;
        normA += valA * valA;
        normB += valB * valB;
        tokA = strtok(NULL, ":");
        tokB = strtok(NULL, ":");
    }

    if (normA == 0.0 || normB == 0.0) {
        printf("0.0000\n");
    } else {
        printf("%.4f\n", dot / (sqrt(normA) * sqrt(normB)));
    }
    return 0;
}
EOF

cat << 'EOF' > /app/lib-embed-tools/Makefile
CC=gcc
CFLAGS=-Wall -O2

all:
	mkdir -p bin
	$(CC) $(CFLAGS) -o bin/cosine_sim src/main.c
EOF

gcc -Wall -O2 -o /opt/oracle/bin/cosine_sim /app/lib-embed-tools/src/main.c -lm

cat << 'EOF' > /opt/oracle/pipeline_oracle.sh
#!/bin/bash
INPUT=$1
while IFS=, read -r id vecA vecB; do
    score=$(/opt/oracle/bin/cosine_sim "$vecA" "$vecB")
    valid=$(echo "$score >= 0.5000" | bc -l)
    if [ "$valid" -eq 1 ]; then
        echo "$id,$score"
    fi
done < "$INPUT"
EOF
chmod +x /opt/oracle/pipeline_oracle.sh

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
