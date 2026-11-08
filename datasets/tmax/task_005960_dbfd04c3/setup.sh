#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip openssl rustc cargo
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/evidence
    cd /home/user/evidence

    # 1. Create the CA
    openssl req -x509 -newkey rsa:2048 -keyout ca.key -out ca.crt -days 365 -nodes -subj "/C=US/ST=State/L=City/O=Attacker CA/CN=AttackerRoot"

    # 2. Create the Valid Certificate (cert_A.crt)
    # Hex payload: "#!/bin/bash\necho 'pwned'" -> 23212f62696e2f626173680a6563686f202770776e656427
    HEX_PAYLOAD="23212f62696e2f626173680a6563686f202770776e656427"
    openssl req -newkey rsa:2048 -keyout cert_A.key -out cert_A.csr -nodes -subj "/C=US/ST=State/L=City/O=Malware/OU=${HEX_PAYLOAD}/CN=ValidLeaf"
    openssl x509 -req -in cert_A.csr -CA ca.crt -CAkey ca.key -CAcreateserial -out cert_A.crt -days 365

    # 3. Create the Decoy Certificate (cert_B.crt)
    # Hex payload: "fake payload" -> 66616b65207061796c6f6164
    DECOY_PAYLOAD="66616b65207061796c6f6164"
    # Generate with a DIFFERENT CA key to make the signature invalid against ca.crt
    openssl req -x509 -newkey rsa:2048 -keyout fake_ca.key -out fake_ca.crt -days 365 -nodes -subj "/C=US/O=Fake CA"
    openssl req -newkey rsa:2048 -keyout cert_B.key -out cert_B.csr -nodes -subj "/C=US/ST=State/L=City/O=Malware/OU=${DECOY_PAYLOAD}/CN=InvalidLeaf"
    openssl x509 -req -in cert_B.csr -CA fake_ca.crt -CAkey fake_ca.key -CAcreateserial -out cert_B.crt -days 365

    # Clean up private keys and CSRs so only evidence remains
    rm -f *.key *.csr *.srl fake_ca.crt

    chmod -R 777 /home/user
