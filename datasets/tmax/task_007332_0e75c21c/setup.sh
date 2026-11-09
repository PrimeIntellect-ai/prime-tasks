#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip procps gcc strace lsof
    pip3 install pytest

    mkdir -p /home/user
    cd /home/user

    # Create the legacy monitor script
    cat << 'EOF' > /home/user/legacy_monitor.sh
#!/bin/bash
cat << 'C_EOF' > /tmp/health_check.c
#include <stdio.h>
#include <string.h>
#include <math.h>

int main(int argc, char **argv) {
    if (argc < 2) return 1;
    double val = sqrt(256.0); // Intentional math dependency
    char buf[16];
    // Buffer overflow vulnerability
    strcpy(buf, argv[1]);
    printf("Status: OK, Val: %f, Input: %s\n", val, buf);
    return 0;
}
C_EOF

# Open file descriptor 4 to the C file
exec 4< /tmp/health_check.c

# Delete the file
rm /tmp/health_check.c

# Hang indefinitely
sleep infinity
EOF

    chmod +x /home/user/legacy_monitor.sh

    # Ensure the script starts when the container is executed
    cat << 'EOF' > /.singularity.d/env/99-monitor.sh
if ! pgrep -f legacy_monitor.sh > /dev/null; then
    nohup /home/user/legacy_monitor.sh >/dev/null 2>&1 &
    sleep 0.5
fi
EOF
    chmod +x /.singularity.d/env/99-monitor.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
