#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git gcc coreutils
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /tmp/oracle.c
#include <stdlib.h>
#include <stdio.h>
#include <string.h>

int main() {
    char buffer[65536];
    size_t len = fread(buffer, 1, sizeof(buffer)-1, stdin);
    buffer[len] = '\0';
    if (strncmp(buffer, "ENCv1|", 6) != 0) {
        printf("ERR: Missing magic\n");
        return 0;
    }

    // Mimic bash input="$(cat)" stripping trailing newlines
    while(len > 0 && buffer[len-1] == '\n') {
        buffer[len-1] = '\0';
        len--;
    }

    FILE *f = fopen("/tmp/oracle_in", "w");
    if (f) {
        fprintf(f, "%s\n", buffer + 6);
        fclose(f);
    }

    system("cat /tmp/oracle_in | tr 'A-Za-z' 'N-ZA-Mn-za-m' | base64");
    return 0;
}
EOF
    gcc -O2 -s /tmp/oracle.c -o /app/oracle_processor
    chmod +x /app/oracle_processor
    rm /tmp/oracle.c

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/encoder_repo
    cd /home/user/encoder_repo
    git init
    git config user.email "dev@example.com"
    git config user.name "Dev"

    cat << 'EOF' > encode.sh
#!/bin/bash
input="$(cat)"
if [[ "$input" != ENCv1\|* ]]; then
    echo "ERR: Missing magic"
    exit 0
fi
echo "${input#ENCv1|}" | tr 'A-Za-z' 'N-ZA-Mn-za-m' | base64
EOF
    chmod +x encode.sh
    git add encode.sh
    git commit -m "Initial commit"

    for i in $(seq 1 141); do
        echo "# Comment $i" >> encode.sh
        git commit -am "Commit $i: minor updates"
    done

    cat << 'EOF' > encode.sh
#!/bin/bash
input="$(cat)"
if [[ "$input" != ENCv1\|* ]]; then
    echo "ERR: Missing magic"
    exit 0
fi
input="${input#ENCv1|}"
input="${input// /}"
echo "$input" | tr 'A-Za-z' 'N-ZA-Mn-za-m' | base64
EOF
    git commit -am "Commit 142: pure bash optimization"

    for i in $(seq 143 200); do
        echo "# Log $i" >> encode.sh
        git commit -am "Commit $i: added logging"
    done

    chown -R user:user /home/user/encoder_repo
    chmod -R 777 /home/user
