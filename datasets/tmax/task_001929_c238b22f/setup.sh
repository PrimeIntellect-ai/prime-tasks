#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 espeak ffmpeg curl
    pip3 install pytest

    # Create directories
    mkdir -p /app/tests/corpus/clean
    mkdir -p /app/tests/corpus/evil
    mkdir -p /home/user/samples

    # Generate the voicemail audio
    espeak -w /app/voicemail.wav "We've identified the fraud pattern. Flag any network that contains a closed triangular cycle of transactions. That means account A sends money to account B, account B sends to account C, and account C sends money back to account A. Any cycle of exactly length three is malicious."

    # Create samples
    cat << 'EOF' > /home/user/samples/clean_sample.csv
source_account,target_account,amount,timestamp
A,B,100,1
B,C,50,2
C,D,25,3
EOF

    cat << 'EOF' > /home/user/samples/evil_sample.csv
source_account,target_account,amount,timestamp
A,B,100,1
B,C,50,2
C,A,25,3
EOF

    # Create clean corpus
    cat << 'EOF' > /app/tests/corpus/clean/clean1.csv
source_account,target_account,amount,timestamp
X,Y,10,1
Y,Z,20,2
Z,W,30,3
EOF

    cat << 'EOF' > /app/tests/corpus/clean/clean2.csv
source_account,target_account,amount,timestamp
A,B,10,1
A,C,20,2
B,D,30,3
C,D,40,4
EOF

    # Create evil corpus
    cat << 'EOF' > /app/tests/corpus/evil/evil1.csv
source_account,target_account,amount,timestamp
U,V,10,1
V,W,20,2
W,U,30,3
EOF

    cat << 'EOF' > /app/tests/corpus/evil/evil2.csv
source_account,target_account,amount,timestamp
M,N,10,1
N,O,20,2
O,P,30,3
P,N,40,4
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
