#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git gcc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/repo
    cd /home/user/repo
    git init
    git config --local user.email "user@example.com"
    git config --local user.name "User"

    cat << 'EOF' > server.c
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

int main() {
    FILE *f = fopen("/home/user/run/server.pid", "w");
    if (!f) {
        perror("Error opening PID file");
        exit(1);
    }
    fprintf(f, "%d\n", getpid());
    fclose(f);

    /* Mock server loop */
    while(1) {
        sleep(1);
    }
    return 0;
}
EOF

    cat << 'EOF' > supervisor.sh
#!/bin/bash
while true; do
    /home/user/repo/server
    sleep 1
done
EOF
    chmod +x supervisor.sh

    cat << 'EOF' > .git/hooks/post-commit
#!/bin/bash
gcc /home/user/repo/server.c -o /home/user/repo/server
pkill -f "/home/user/repo/supervisor.sh" || true
pkill -f "/home/user/repo/server" || true
nohup /home/user/repo/supervisor.sh > /home/user/supervisor.log 2>&1 &
EOF
    chmod +x .git/hooks/post-commit

    git add server.c supervisor.sh
    git commit -m "Initial commit"

    chmod -R 777 /home/user
