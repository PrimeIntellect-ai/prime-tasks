#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc expect curl bash
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/lb_daemon.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main() {
    // Bug 1: Segfault if UPSTREAM_CONF is not set
    char* conf_path = getenv("UPSTREAM_CONF");
    FILE* f = fopen(conf_path, "r");
    if(f) fclose(f);

    // Bug 2: Hardcoded privileged port
    int port = 80;

    printf("Starting load balancer on port %d using conf %s\n", port, conf_path);
    return 0;
}
EOF

    cat << 'EOF' > /home/user/init_upstream.sh
#!/bin/bash
read -p "Enter upstream port 1: " p1
read -p "Enter upstream port 2: " p2
read -p "Enter upstream port 3: " p3

echo "upstream1:127.0.0.1:$p1" > /home/user/upstream.conf
echo "upstream2:127.0.0.1:$p2" >> /home/user/upstream.conf
echo "upstream3:127.0.0.1:$p3" >> /home/user/upstream.conf
echo "Configuration saved to /home/user/upstream.conf"
EOF

    chmod +x /home/user/init_upstream.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
