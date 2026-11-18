#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc git coreutils
    pip3 install pytest

    # Create oracle
    mkdir -p /app
    cat << 'EOF' > /app/oracle.c
#include <stdio.h>
int main() {
    int c;
    while ((c = getchar()) != EOF) {
        printf("%02X", c ^ 0x2A);
    }
    return 0;
}
EOF
    gcc -O2 /app/oracle.c -o /app/oracle
    strip /app/oracle
    rm /app/oracle.c

    # Create user
    useradd -m -s /bin/bash user || true

    # Create git repository
    mkdir -p /home/user/log-obfuscator
    cd /home/user/log-obfuscator
    git init
    git config user.name "Dev"
    git config user.email "dev@example.com"

    cat << 'EOF' > obfuscator.sh
#!/bin/bash
od -v -A n -t u1 | while read -r line; do
    for byte in $line; do
        printf "%02X" "$(( byte ^ 0x2A ))"
    done
done
EOF
    chmod +x obfuscator.sh
    git add obfuscator.sh
    git commit -m "Initial commit"

    for i in $(seq 2 124); do
        echo "# commit $i" >> obfuscator.sh
        git commit -am "Commit $i"
    done

    # Commit 125: introduce formatting bug
    cat << 'EOF' > obfuscator.sh
#!/bin/bash
# performance optimization
od -v -A n -t u1 | while read -r line; do
    for byte in $line; do
        printf "%X" "$(( byte ^ 0x2A ))"
    done
done
EOF
    git commit -am "Optimize formatting"

    for i in $(seq 126 139); do
        echo "# commit $i" >> obfuscator.sh
        git commit -am "Commit $i"
    done

    # Commit 140: introduce space handling bug
    cat << 'EOF' > obfuscator.sh
#!/bin/bash
# performance optimization
od -v -A n -t u1 | while read line; do
    for byte in $line; do
        printf "%X" "$(( byte ^ 0x2A ))"
    done
done
EOF
    git commit -am "Refactor read loop"

    for i in $(seq 141 200); do
        echo "# commit $i" >> obfuscator.sh
        git commit -am "Commit $i"
    done

    chown -R user:user /home/user
    chmod -R 777 /home/user
