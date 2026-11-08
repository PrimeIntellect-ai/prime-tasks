#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip wget tar default-jre jq curl
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/transactions.ttl
@prefix ex: <http://example.org/> .

ex:T1 ex:waitsFor ex:R1 .
ex:R1 ex:heldBy ex:T2 .
ex:T2 ex:waitsFor ex:R2 .
ex:R2 ex:heldBy ex:T1 .

ex:T3 ex:waitsFor ex:R3 .
ex:R3 ex:heldBy ex:T4 .

ex:T5 ex:waitsFor ex:R4 .
ex:R4 ex:heldBy ex:T6 .
ex:T6 ex:waitsFor ex:R5 .
ex:R5 ex:heldBy ex:T5 .
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
