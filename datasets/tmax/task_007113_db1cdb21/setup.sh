#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils openssl jq gawk coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/artifacts/templates

    # 1. Create the ELF binary and manifest
    cat << 'EOF' > /tmp/dummy.c
#include <stdio.h>
const char* version = "v1.2.3-secure";
int main() {
    printf("Server %s\n", version);
    return 0;
}
EOF
    gcc -o /home/user/artifacts/web_server_daemon /tmp/dummy.c
    objcopy -O binary --only-section=.rodata /home/user/artifacts/web_server_daemon /tmp/rodata.bin
    sha256sum /tmp/rodata.bin | awk '{print $1}' > /home/user/artifacts/manifest.txt

    # 2. Create the certificates
    cd /tmp
    # Root CA
    openssl req -x509 -newkey rsa:2048 -days 365 -nodes -keyout root_key.pem -out root_ca.pem -subj "/CN=RootCA"
    # Intermediate CA
    openssl req -newkey rsa:2048 -nodes -keyout int_key.pem -out int_req.pem -subj "/CN=IntermediateCA"
    echo "basicConstraints=critical,CA:TRUE" > extfile.txt
    openssl x509 -req -in int_req.pem -CA root_ca.pem -CAkey root_key.pem -CAcreateserial -out int_cert.pem -days 365 -extfile extfile.txt
    # Leaf Cert
    openssl req -newkey rsa:2048 -nodes -keyout leaf_key.pem -out leaf_req.pem -subj "/CN=localhost"
    openssl x509 -req -in leaf_req.pem -CA int_cert.pem -CAkey int_key.pem -CAcreateserial -out leaf_cert.pem -days 365

    cp root_ca.pem /home/user/artifacts/root_ca.pem
    cat leaf_cert.pem int_cert.pem > /home/user/artifacts/server_certs.pem

    # 3. Create templates
    cat << 'EOF' > /home/user/artifacts/templates/index.html
<html><body>Hello World</body></html>
EOF
    cat << 'EOF' > /home/user/artifacts/templates/admin.html
<html><script>let x = eval(document.location.hash.substring(1));</script></html>
EOF
    cat << 'EOF' > /home/user/artifacts/templates/dashboard.html
<html><script>console.log("no eval here");</script></html>
EOF
    cat << 'EOF' > /home/user/artifacts/templates/profile.html
<html><script>eval(userInput);</script></html>
EOF

    chown -R user:user /home/user/artifacts
    chmod -R 777 /home/user
