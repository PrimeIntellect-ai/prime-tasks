#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo rustc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/raw
    mkdir -p /home/user/processed

    cat << 'EOF' > /home/user/raw/data.csv
id,name,email,dob,ssn,notes
1,Alice Smith, ALICE@example.com ,1990-01-01,123-45-6789,Regular user
2,Bob Jones,bob@example.com,1985-05-15,987-65-4321,"This is a multiline
note for Bob.
It has newlines."
1,Alice Smith,alice@example.com,1990-01-01,123-45-6789,Duplicate ID should be dropped
3,Charlie Brown,charlie.example.com,1992-11-20,111-22-3333,Invalid email without at symbol
4,David Lee,david@example.com,10-10-2000,222-33-4444,Invalid DOB format
5,Eve Davis,eve@example.com,1995-12-31,333-44-5555,Valid user record
EOF

    chmod -R 777 /home/user
