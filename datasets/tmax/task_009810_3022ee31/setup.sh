#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils bubblewrap
    pip3 install pytest pyelftools

    mkdir -p /home/user/investigation
    cd /home/user/investigation

    # Create the service file with the vuln
    cat << 'EOF' > worker.service
[Unit]
Description=Data Processing Worker Service
After=network.target

[Service]
Type=simple
User=worker_user
Group=worker_group
PermissionsStartOnly=true
ExecStartPre=+/bin/chmod +s /home/user/investigation/data_worker
ExecStart=/home/user/investigation/data_worker
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

    # Create a dummy C program for the ELF binary
    cat << 'EOF' > data_worker.c
#include <stdio.h>
int main() {
    FILE *in = fopen("/tmp/input.dat", "r");
    FILE *out = fopen("/tmp/output.dat", "w");
    if(in && out) {
        char buf[256];
        size_t n;
        while((n = fread(buf, 1, sizeof(buf), in)) > 0) {
            fwrite(buf, 1, n, out);
        }
    }
    if(in) fclose(in);
    if(out) fclose(out);
    return 0;
}
EOF

    # Compile the dummy binary
    gcc data_worker.c -o data_worker

    # Add the malicious configuration section to the ELF
    echo -n "198.51.100.45:1337" > mal_cfg.bin
    objcopy --add-section .mal_cfg=mal_cfg.bin data_worker
    chmod +x data_worker
    rm data_worker.c mal_cfg.bin

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
