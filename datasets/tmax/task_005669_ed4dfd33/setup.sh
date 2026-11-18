#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip libc-bin
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/raw_data
    mkdir -p /home/user/output

    cat << 'EOF' > /home/user/raw_data/batch1_utf8.csv
transaction_id,customer_name,email,ssn,amount,timestamp
T001,Alice Jones,alice.j@test.com,111-22-3333,150.00,2023-10-01 10:00:00
T002,Bob Smith,bob.smith@domain.org,444-55-6666,200.50,2023-10-01 10:05:00
T001,Alice Jones,alice.j@test.com,111-22-3333,150.00,2023-10-01 10:15:00
EOF

    cat << 'EOF' | iconv -f UTF-8 -t ISO-8859-1 > /home/user/raw_data/batch2_iso.csv
transaction_id,customer_name,email,ssn,amount,timestamp
T003,Chloë Grace,chloe@website.net,777-88-9999,300.00,2023-10-01 11:00:00
T002,Bob Smith,bob.smith@domain.org,444-55-6666,200.50,2023-10-01 10:02:00
T004,David Müller,d.muller@corp.de,000-11-2222,50.25,2023-10-01 12:00:00
EOF

    cat << 'EOF' | iconv -f UTF-8 -t UTF-16 > /home/user/raw_data/batch3_utf16.csv
transaction_id,customer_name,email,ssn,amount,timestamp
T004,David Müller,d.muller@corp.de,000-11-2222,50.25,2023-10-01 12:30:00
T005,Eva Green,eva.g@test.com,333-44-5555,99.99,2023-10-01 13:00:00
EOF

    chown -R user:user /home/user/raw_data
    chown -R user:user /home/user/output
    chmod -R 777 /home/user
