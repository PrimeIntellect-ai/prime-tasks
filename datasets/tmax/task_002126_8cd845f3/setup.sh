#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc coreutils jq binutils
    pip3 install pytest

    mkdir -p /home/user/incident

    # Create the C source for the malicious payload
    cat << 'EOF' > /tmp/payload.c
#include <stdlib.h>
#include <unistd.h>

int main() {
    // Attempting to exploit a hypothetical vulnerable SUID binary
    char *args[] = { "/usr/local/sbin/vuln_backup_manager", "--restore", "exploit", NULL };
    execv(args[0], args);
    return 0;
}
EOF

    # Compile the ELF binary
    gcc -O2 /tmp/payload.c -o /tmp/payload.elf

    # Get MD5 of the payload for verification
    PAYLOAD_MD5=$(md5sum /tmp/payload.elf | awk '{print $1}')

    # Base64 encode the binary
    B64_PAYLOAD=$(base64 -w 0 /tmp/payload.elf)

    # Create the fake HTTP traffic file
    cat << EOF > /home/user/incident/upload_traffic.txt
POST /api/v1/upload HTTP/1.1
Host: 10.0.5.50
User-Agent: Mozilla/5.0
Accept: */*
Content-Type: multipart/form-data; boundary=----WebKitFormBoundary7MA4YWxkTrZu0gW
Content-Length: 8543

------WebKitFormBoundary7MA4YWxkTrZu0gW
Content-Disposition: form-data; name="upload_file"; filename="../../../../../var/www/html/uploads/system_update"
Content-Type: application/octet-stream
Content-Transfer-Encoding: base64

${B64_PAYLOAD}
------WebKitFormBoundary7MA4YWxkTrZu0gW--
EOF

    # Save the expected MD5 to a hidden file for test verification
    echo "$PAYLOAD_MD5" > /home/user/incident/.expected_md5

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
