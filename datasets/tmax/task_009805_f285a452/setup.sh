#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip openssl gcc binutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user
    cd /home/user

    # 1. Generate Root CA
    openssl req -x509 -newkey rsa:2048 -days 3650 -nodes -keyout root.key -out root.pem -subj "/C=US/O=EvilCorp/CN=EvilCorp Root CA"

    # 2. Generate Intermediate CA
    openssl req -newkey rsa:2048 -nodes -keyout intermediate.key -out intermediate.csr -subj "/C=US/O=EvilCorp/CN=EvilCorp Intermediate CA"

    cat <<EOF > int.ext
basicConstraints=CA:TRUE,pathlen:0
keyUsage=keyCertSign,cRLSign
EOF
    openssl x509 -req -in intermediate.csr -CA root.pem -CAkey root.key -CAcreateserial -out intermediate.pem -days 1825 -extfile int.ext

    # 3. Generate Leaf Certificate
    openssl req -newkey rsa:2048 -nodes -keyout leaf.key -out leaf.csr -subj "/C=US/O=EvilCorp/CN=target.evilcorp.local"

    cat <<EOF > leaf.ext
basicConstraints=CA:FALSE
keyUsage=digitalSignature,keyEncipherment
extendedKeyUsage=serverAuth
EOF
    openssl x509 -req -in leaf.csr -CA intermediate.pem -CAkey intermediate.key -CAcreateserial -out leaf.pem -days 365 -extfile leaf.ext

    # 4. Create the traffic_certs.pem (Leaf + Intermediate)
    cat leaf.pem intermediate.pem > traffic_certs.pem

    # 5. Create a C file embedding the Root CA
    echo '#include <stdio.h>' > client.c
    echo 'const char root_ca[] =' >> client.c
    sed 's/^/"/; s/$/\\n"/' root.pem >> client.c
    echo ';' >> client.c
    echo 'int main() {' >> client.c
    echo '    printf("Starting client...\\n");' >> client.c
    echo '    return 0;' >> client.c
    echo '}' >> client.c

    # 6. Compile the binary and strip it
    gcc -O2 -o client_bin client.c
    strip client_bin

    # 7. Cleanup
    rm -f root.key root.pem root.srl intermediate.key intermediate.csr intermediate.pem int.ext leaf.key leaf.csr leaf.pem leaf.ext client.c

    chmod -R 777 /home/user
