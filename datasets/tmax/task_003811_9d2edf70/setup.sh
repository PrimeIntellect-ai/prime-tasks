#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc
pip3 install pytest

mkdir -p /home/user/bin /home/user/logs /home/user/data

# 1. Create and compile the binary
cat << 'EOF' > /home/user/bin/data_ingester.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main() {
    // Hardcoded key for RE string extraction
    const char* key = "XOR_KEY=b7f9a2d4";

    char* env = getenv("PIPELINE_ENV");
    if(env == NULL || strcmp(env, "PROD") != 0) {
        fprintf(stderr, "FATAL: PIPELINE_ENV not set to PROD. Current value: %s\n", env ? env : "NULL");
        fprintf(stderr, "Core dumped.\n");
        return 1;
    }
    printf("Service running successfully in PROD mode. Listening for data...\n");
    return 0;
}
EOF

gcc /home/user/bin/data_ingester.c -o /home/user/bin/data_ingester
rm /home/user/bin/data_ingester.c

# 2. Create the broken start script
cat << 'EOF' > /home/user/bin/start.sh
#!/bin/bash
export PIPELINE_ENV=STAGING
/home/user/bin/data_ingester >> /home/user/logs/ingester.log 2>&1
EOF
chmod +x /home/user/bin/start.sh

# Run it once to populate the log
/home/user/bin/start.sh || true

# 3. Create the encrypted backlog data using Python
python3 -c '
key = b"b7f9a2d4"
message = b"CRITICAL_TELEMETRY_RECOVERED_SUCCESSFULLY_9921"
encrypted = bytearray()
for i in range(len(message)):
    encrypted.append(message[i] ^ key[i % len(key)])
with open("/home/user/data/backlog.enc", "wb") as f:
    f.write(encrypted)
'

useradd -m -s /bin/bash user || true
chown -R user:user /home/user/bin /home/user/logs /home/user/data
chmod -R 777 /home/user
