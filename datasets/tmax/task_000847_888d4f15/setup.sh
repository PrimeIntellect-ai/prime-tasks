#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc jq gdb binutils coreutils gawk sed
pip3 install pytest

mkdir -p /app/data /app/tests/corpus/clean /app/tests/corpus/evil /app/bin

# Create log_ingest source and compile
cat << 'EOF' > /tmp/log_ingest.c
#include <stdio.h>
#include <string.h>

int main() {
    char line[8192];
    while (fgets(line, sizeof(line), stdin)) {
        int in_string = 0;
        int len = strlen(line);
        for (int i = 0; i < len; i++) {
            if (line[i] == '"' && (i == 0 || line[i-1] != '\\')) {
                in_string = !in_string;
            }
            if (in_string && line[i] >= 0 && line[i] <= 0x1F) {
                int *p = NULL;
                *p = 1; // Segfault on control char in string
            }
            if (line[i] == '\\' && i + 1 < len && line[i+1] == 'u') {
                for (int j = 0; j < 4; j++) {
                    int c = line[i + 2 + j];
                    if (!((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F'))) {
                        int *p = NULL;
                        *p = 1; // Segfault on bad unicode hex
                    }
                }
            }
        }
        printf("%s", line);
    }
    return 0;
}
EOF

gcc -O2 /tmp/log_ingest.c -o /app/bin/log_ingest
strip /app/bin/log_ingest
rm /tmp/log_ingest.c
chmod +x /app/bin/log_ingest

# Clean corpus examples
cat << 'EOF' > /app/tests/corpus/clean/01.log
[2023/10/01 12:00:00] {"event": "login", "user": "alice\u00A9"}
[01-10-2023 12:00:01] {"event": "click", "target": "button"}
EOF

# Evil corpus examples (malformed unicode)
cat << 'EOF' > /app/tests/corpus/evil/01_bad_unicode.log
[2023/10/01 12:00:02] {"event": "error", "msg": "failed \uZZZZ string"}
EOF

# Evil corpus examples (control character)
printf '[2023/10/01 12:00:03] {"event": "error", "msg": "tab\tbyte"}\n' > /app/tests/corpus/evil/02_control_char.log

# Sample for the agent
cat /app/tests/corpus/clean/01.log /app/tests/corpus/evil/01_bad_unicode.log > /app/data/sample.log

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
chmod -R 777 /app
