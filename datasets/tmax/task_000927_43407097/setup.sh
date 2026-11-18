#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc socat nmap binutils
    pip3 install pytest

    # Create directories
    mkdir -p /app
    mkdir -p /home/user/logs

    # Create arc_tool source
    cat << 'EOF' > /app/arc_tool.c
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char *argv[]) {
    if (argc != 3) {
        fprintf(stderr, "Usage: %s <input> <output>\n", argv[0]);
        return 1;
    }

    FILE *fin = fopen(argv[1], "rb");
    if (!fin) {
        return 1;
    }

    FILE *fout = fopen(argv[2], "wb");
    if (!fout) {
        fclose(fin);
        return 1;
    }

    unsigned char magic[4] = {0x41, 0x52, 0x43, 0x31};
    fwrite(magic, 1, 4, fout);

    int c;
    while ((c = fgetc(fin)) != EOF) {
        fputc(c ^ 0x4B, fout);
    }

    fclose(fin);
    fclose(fout);
    return 0;
}
EOF

    # Compile and strip arc_tool
    gcc -O2 /app/arc_tool.c -o /app/arc_tool
    strip /app/arc_tool
    chmod +x /app/arc_tool
    rm /app/arc_tool.c

    # Generate sample logs
    cat << 'EOF' > /home/user/logs/app_2023-10-15.log
--- RECORD START ---
DATE: 2023-10-15
LEVEL: INFO
MSG: System started.
--- RECORD END ---
--- RECORD START ---
DATE: 2023-10-15
LEVEL: CRITICAL
MSG: Out of memory exception in worker thread.
--- RECORD END ---
--- RECORD START ---
DATE: 2023-10-15
LEVEL: WARNING
MSG: Disk space low.
--- RECORD END ---
EOF

    cat << 'EOF' > /home/user/logs/app_2023-10-16.log
--- RECORD START ---
DATE: 2023-10-16
LEVEL: CRITICAL
MSG: Database connection lost.
--- RECORD END ---
--- RECORD START ---
DATE: 2023-10-16
LEVEL: INFO
MSG: User login.
--- RECORD END ---
EOF

    cat << 'EOF' > /home/user/logs/app_2023-10-17.log
--- RECORD START ---
DATE: 2023-10-17
LEVEL: INFO
MSG: Backup completed.
--- RECORD END ---
--- RECORD START ---
DATE: 2023-10-17
LEVEL: CRITICAL
MSG: CPU temperature critical.
--- RECORD END ---
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
