#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make bash
    pip3 install pytest

    mkdir -p /app/cookie-extractor-1.0
    mkdir -p /opt/oracle

    cat << 'EOF' > /app/cookie-extractor-1.0/main.c
#include <stdio.h>
#include <string.h>

int main(int argc, char *argv[]) {
    char buffer[1024];
    if (fgets(buffer, sizeof(buffer), stdin) != NULL) {
        char *token = strstr(buffer, "CommandToken=");
        if (token) {
            token += 13;
            char *end = strchr(token, ';');
            if (end) *end = '\0';
            char *newline = strchr(token, '\n');
            if (newline) *newline = '\0';
            char *carriage = strchr(token, '\r');
            if (carriage) *carriage = '\0';
            printf("%s\n", token);
        }
    }
    return 0;
}
EOF

    cat << 'EOF' > /app/cookie-extractor-1.0/Makefile
all:
	gcc -o cookie-extractor extractor.c
EOF

    cat << 'EOF' > /opt/oracle/generate_auth_oracle.sh
#!/bin/bash
read -r line
token=$(echo "$line" | /app/cookie-extractor-1.0/cookie-extractor)
decrypted=""
for (( i=0; i<${#token}; i+=2 )); do
    hex_byte=${token:$i:2}
    val=$(( 16#$hex_byte ^ 16#5A ))
    char=$(printf "\\x$(printf %x $val)")
    decrypted="${decrypted}${char}"
done
echo "restrict,command=\"${decrypted}\" ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEx1234567890abcdefghijklmnopqrstuvwxyz123 dummy@key"
EOF

    chmod +x /opt/oracle/generate_auth_oracle.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
