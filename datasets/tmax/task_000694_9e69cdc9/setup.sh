#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest rdflib

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/locks.ttl
@prefix ex: <http://example.org/> .

ex:T1 a ex:Transaction ;
    ex:holds ex:R1 ;
    ex:waitsFor ex:R2 .

ex:T2 a ex:Transaction ;
    ex:holds ex:R2 ;
    ex:waitsFor ex:R1 .

ex:T3 a ex:Transaction ;
    ex:holds ex:R3 ;
    ex:waitsFor ex:R4 .

ex:T4 a ex:Transaction ;
    ex:holds ex:R4 ;
    ex:waitsFor ex:R5 .

ex:T5 a ex:Transaction ;
    ex:holds ex:R5 ;
    ex:waitsFor ex:R3 .

ex:T6 a ex:Transaction ;
    ex:holds ex:R6 ;
    ex:waitsFor ex:R7 .

ex:T7 a ex:Transaction ;
    ex:holds ex:R7 ;
    ex:waitsFor ex:R8 .

ex:T8 a ex:Transaction ;
    ex:holds ex:R8 .
EOF

    chmod -R 777 /home/user
