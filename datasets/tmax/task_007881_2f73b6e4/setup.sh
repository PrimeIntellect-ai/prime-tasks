#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Install necessary tools for the task
    apt-get install -y gcc binutils cargo

    # Create user
    useradd -m -s /bin/bash user || true

    # Setup task files
    mkdir -p /home/user

    # Create the guardian binary containing the secret passphrase
    cat << 'EOF' > /home/user/guardian.c
#include <stdio.h>
#include <string.h>

int main(int argc, char *argv[]) {
    // The secret passphrase is "NovusOrdoSeclorum"
    const char* secret = "NovusOrdoSeclorum";
    if (argc > 1 && strcmp(argv[1], secret) == 0) {
        printf("Authorized.\n");
        return 0;
    }
    printf("Denied.\n");
    return 1;
}
EOF
    gcc -O2 /home/user/guardian.c -o /home/user/guardian
    strip /home/user/guardian
    rm /home/user/guardian.c

    # Create the static analysis scanner
    cat << 'EOF' > /home/user/scan_payload.sh
#!/bin/bash
if [ -z "$1" ]; then
    echo "Usage: $0 <binary>"
    exit 1
fi

if strings "$1" | grep -E -i 'EXECUTE|PAYLOAD|NovusOrdoSeclorum' > /dev/null; then
    echo "MALWARE DETECTED"
    exit 1
else
    echo "CLEAN"
    exit 0
fi
EOF
    chmod +x /home/user/scan_payload.sh

    # Ensure correct ownership and permissions
    chown -R user:user /home/user
    chmod -R 777 /home/user
