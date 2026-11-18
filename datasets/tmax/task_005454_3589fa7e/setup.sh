#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils openssl golang-go
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    cd /home/user

    # Generate Root CA
    openssl genrsa -out rootCA.key 2048
    openssl req -x509 -new -nodes -key rootCA.key -sha256 -days 1024 -out rootCA.pem -subj "/C=US/ST=State/L=City/O=Org/CN=RootCA"

    # Generate Intermediate CA
    openssl genrsa -out intermediate.key 2048
    openssl req -new -key intermediate.key -out intermediate.csr -subj "/C=US/ST=State/L=City/O=Org/CN=IntermediateCA"
    cat <<EOF > v3_inter.ext
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always,issuer
basicConstraints = critical, CA:true, pathlen:0
keyUsage = critical, digitalSignature, cRLSign, keyCertSign
EOF
    openssl x509 -req -in intermediate.csr -CA rootCA.pem -CAkey rootCA.key -CAcreateserial -out intermediate.pem -days 500 -sha256 -extfile v3_inter.ext

    # Generate Leaf Cert
    openssl genrsa -out leaf.key 2048
    openssl req -new -key leaf.key -out leaf.csr -subj "/C=US/ST=State/L=City/O=Org/CN=audit.internal"
    cat <<EOF > v3_leaf.ext
authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
keyUsage = digitalSignature, nonRepudiation, keyEncipherment, dataEncipherment
subjectAltName = @alt_names
[alt_names]
DNS.1 = audit.internal
EOF
    openssl x509 -req -in leaf.csr -CA intermediate.pem -CAkey intermediate.key -CAcreateserial -out leaf.pem -days 365 -sha256 -extfile v3_leaf.ext

    # Create server_chain.pem (leaf first, then intermediate)
    cat leaf.pem intermediate.pem > server_chain.pem

    # Create dummy ELF binary and inject rootCA.pem into .auth_root section
    echo "int main(){return 0;}" > dummy.c
    gcc dummy.c -o legacy_processor
    objcopy --add-section .auth_root=rootCA.pem legacy_processor legacy_processor

    # Create binary audit file (Little Endian)
    echo -ne '\x01\x00\x04\x00JUNK\x77\x00\x10\x00SECURE_AUDIT_998\x02\x00\x02\x00NO' > audit_data.bin

    # Cleanup temp files
    rm -f rootCA.key rootCA.pem intermediate.key intermediate.csr intermediate.pem leaf.key leaf.csr leaf.pem dummy.c *.srl v3_inter.ext v3_leaf.ext

    chmod -R 777 /home/user
