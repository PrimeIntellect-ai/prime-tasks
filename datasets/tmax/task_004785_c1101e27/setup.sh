#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make openssh-server openssh-client iproute2
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/src
    mkdir -p /home/user/.ssh
    ssh-keygen -t rsa -N "" -f /home/user/.ssh/id_rsa
    cat /home/user/.ssh/id_rsa.pub >> /home/user/.ssh/authorized_keys
    chmod 600 /home/user/.ssh/authorized_keys
    chown -R user:user /home/user/.ssh

    cat << 'EOF' > /home/user/src/service.c
#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include <unistd.h>

int main() {
    FILE *f = fopen("/var/log/service.log", "w");
    if (!f) {
        perror("Failed to open log");
        return 1;
    }

    time_t t = time(NULL);
    struct tm *tm_info = localtime(&t);
    char buffer[26];
    strftime(buffer, 26, "%Z", tm_info);

    fprintf(f, "[INIT] Service started in timezone: %s\n", buffer);
    fclose(f);

    // Simulate long running service
    sleep(3600);
    return 0;
}
EOF

    cat << 'EOF' > /home/user/run_service.sh
#!/bin/bash
# Broken startup script
export TZ=America/New_York
ssh -L 8888:127.0.0.1:9999 user@127.0.0.1
/home/user/bin/service &
EOF
    chmod +x /home/user/run_service.sh

    # Setup sshd configuration for testing
    mkdir -p /run/sshd
    chmod 755 /run/sshd

    chmod -R 777 /home/user
