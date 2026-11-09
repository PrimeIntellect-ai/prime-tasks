#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak zip unzip git sqlite3 build-essential
    pip3 install pytest

    mkdir -p /app

    # Generate audio fixture
    espeak -w /app/voicemail.wav "The archive password is gamma ray burst."

    # Create meta.db
    sqlite3 /app/meta.db "CREATE TABLE metadata (id INTEGER PRIMARY KEY, token TEXT, value TEXT);"
    sqlite3 /app/meta.db "INSERT INTO metadata (token, value) VALUES ('TOKEN_99A', 'secret_data');"

    # Create Git repository and zip it
    mkdir -p /tmp/repo/src
    cd /tmp/repo
    git init
    git config user.email "test@example.com"
    git config user.name "Test"

    cat << 'EOF' > src/chunker.c
#include <stdio.h>
int main() {
    printf("chunker\n");
    return 0;
}
EOF

    cat << 'EOF' > parser.sh
#!/bin/bash
# API_TOKEN=TOKEN_99A
echo "parser"
EOF

    git add .
    git commit -m "initial commit"

    rm parser.sh
    git add parser.sh
    git commit -m "revert bash experiment"

    cd /tmp
    zip -P "gamma ray burst" -r /app/repo.zip repo

    # Create legacy oracle
    cat << 'EOF' > /tmp/oracle.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char *argv[]) {
    if (argc != 2) return 1;
    FILE *f = fopen(argv[1], "rb");
    if (!f) return 1;

    fseek(f, 0, SEEK_END);
    long size = ftell(f);
    fseek(f, 0, SEEK_SET);

    if (size < 16) {
        printf("{\"status\": \"error\", \"reason\": \"file_too_short\"}\n");
        fclose(f);
        return 1;
    }

    char magic[4];
    if (fread(magic, 1, 4, f) != 4) {
        printf("{\"status\": \"error\", \"reason\": \"file_too_short\"}\n");
        fclose(f);
        return 1;
    }

    if (strncmp(magic, "AUDI", 4) != 0) {
        printf("{\"status\": \"error\", \"reason\": \"corrupt_header\"}\n");
        fclose(f);
        return 1;
    }

    printf("{\"status\": \"success\", \"token\": \"TOKEN_99A\", \"data\": \"secret_data\"}\n");
    fclose(f);
    return 0;
}
EOF
    gcc -o /app/legacy_oracle /tmp/oracle.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
