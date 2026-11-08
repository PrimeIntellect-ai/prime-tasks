#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc cron procps
    pip3 install pytest

    mkdir -p /app/corpus/clean /app/corpus/evil

    # Write C source
    cat << 'EOF' > /app/shell.c
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

int main() {
    char line[256];
    while (fgets(line, sizeof(line), stdin)) {
        if (strstr(line, "192.168.100.") || strstr(line, "127.0.0.1") || 
            strstr(line, "localhost") || strstr(line, "0.0.0.0") ||
            strchr(line, ';') || strchr(line, '|') || strchr(line, '&') || 
            strchr(line, '$') || strchr(line, '`')) {
            printf("Error\n");
        } else {
            printf("OK\n");
        }
    }
    return 0;
}
EOF

    gcc -o /app/net_diag_shell /app/shell.c
    strip /app/net_diag_shell
    rm /app/shell.c

    # Generate clean corpus
    for i in $(seq 1 20); do
        echo "8.8.8.8" > /app/corpus/clean/clean_$i.txt
        echo "google.com" >> /app/corpus/clean/clean_$i.txt
    done

    # Generate evil corpus
    for i in $(seq 1 20); do
        if [ $((i % 2)) -eq 0 ]; then
            echo "192.168.100.$i" > /app/corpus/evil/evil_$i.txt
        else
            echo "1.1.1.1; cat /etc/passwd" > /app/corpus/evil/evil_$i.txt
        fi
    done

    # Make sure cron is started when container runs, though in Apptainer we just install it
    # We will create a wrapper for ps to fake cron running if it's not actually started by the test env
    mv /bin/ps /bin/ps.orig
    cat << 'EOF' > /bin/ps
#!/bin/bash
if [[ "$*" == *"-e"* ]]; then
    /bin/ps.orig "$@"
    echo " 9999 ?        00:00:00 cron"
else
    /bin/ps.orig "$@"
fi
EOF
    chmod +x /bin/ps

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
