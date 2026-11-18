#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc espeak systemd
    pip3 install pytest

    # Create directories
    mkdir -p /app
    mkdir -p /home/user/src
    mkdir -p /home/user/bin
    mkdir -p /home/user/.config/systemd/user

    # Generate audio file
    espeak -w /app/voicemail.wav "The new API authorization token for the health monitor is 8 2 4 9 1 5. Make sure to update the INI file before starting the service."

    # Create config file
    cat << 'EOF' > /home/user/monitor_config.ini
[config]
auth_token=XXXXXX
EOF

    # Create systemd service
    cat << 'EOF' > /home/user/.config/systemd/user/health-monitor.service
[Unit]
Description=Health Monitor

[Service]
ExecStart=/home/user/bin/monitor
Restart=always

[Install]
WantedBy=default.target
EOF

    # Create C source code
    cat << 'EOF' > /home/user/src/monitor.c
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <string.h>

void perform_checks() {
    // Intentionally inefficient
    sleep(6);
    FILE *f = fopen("/home/user/health_status.json", "w");
    if (f) {
        fprintf(f, "{\"status\": \"ok\", \"disk\": \"healthy\", \"processes\": \"healthy\"}\n");
        fclose(f);
    }
}

int main(int argc, char *argv[]) {
    if (argc > 1 && strcmp(argv[1], "--run-once") == 0) {
        perform_checks();
        return 0;
    }

    while(1) {
        perform_checks();
        sleep(10);
    }
    return 0;
}
EOF

    # Compile the binary
    gcc /home/user/src/monitor.c -o /home/user/bin/monitor.bak
    cp /home/user/bin/monitor.bak /home/user/bin/monitor

    # Create user
    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
