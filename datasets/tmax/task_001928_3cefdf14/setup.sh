#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip make gcc gawk
    pip3 install pytest

    # Create directories
    mkdir -p /app/fast-extractor-1.0
    mkdir -p /opt/oracle

    # Create main.c
    cat << 'EOF' > /app/fast-extractor-1.0/main.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifndef MAX_LEN
#define MAX_LEN 10
#endif

int main() {
    char buf[MAX_LEN];
    if (fgets(buf, sizeof(buf), stdin)) {
        if (strchr(buf, '\n') == NULL && !feof(stdin)) {
            fprintf(stderr, "Line too long! Max length is %d\n", MAX_LEN);
            return 1;
        }
        printf("Success\n");
    }
    return 0;
}
EOF

    # Create Makefile (must use tabs)
    cat << 'EOF' > /app/fast-extractor-1.0/Makefile
CFLAGS = -O2 -Wall -DMAX_LEN=10

fast-extract: main.c
	$(CC) $(CFLAGS) -o fast-extract main.c

clean:
	rm -f fast-extract
EOF

    # Create oracle script
    cat << 'EOF' > /opt/oracle/transform_oracle.sh
#!/bin/bash
iconv -f Windows-1252 -t UTF-8 | awk -F':' 'BEGIN{OFS=":"} $2=="CRITICAL" {$2="RESOLVED"; print}'
EOF
    chmod +x /opt/oracle/transform_oracle.sh

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
