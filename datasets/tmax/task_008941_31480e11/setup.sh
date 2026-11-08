#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip openssh-client gawk gcc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/pubkeys
    cd /home/user

    # Generate keys
    ssh-keygen -t rsa -b 2048 -f /home/user/pubkeys/alice -N "" -q
    ssh-keygen -t rsa -b 2048 -f /home/user/pubkeys/bob -N "" -q
    ssh-keygen -t rsa -b 2048 -f /home/user/pubkeys/charlie -N "" -q

    # Extract fingerprints
    FP_ALICE=$(ssh-keygen -l -f /home/user/pubkeys/alice.pub | awk '{print $2}')
    FP_BOB=$(ssh-keygen -l -f /home/user/pubkeys/bob.pub | awk '{print $2}')
    FP_CHARLIE=$(ssh-keygen -l -f /home/user/pubkeys/charlie.pub | awk '{print $2}')

    # Create auth log
    cat <<EOF > /home/user/auth_events.log
May 14 10:00:01 server sshd[1234]: Accepted publickey for admin from 10.0.0.5 port 50000 ssh2: RSA $FP_ALICE
May 14 10:05:22 server sshd[1235]: Disconnected from authenticating user admin 10.0.0.6 port 50001
May 14 10:15:33 server sshd[1236]: Accepted publickey for admin from 10.0.0.7 port 50002 ssh2: RSA $FP_BOB
May 14 10:20:00 server sshd[1237]: Accepted publickey for admin from 10.0.0.5 port 50003 ssh2: RSA $FP_ALICE
EOF

    # Create tokens file
    cat <<EOF > /home/user/tokens.txt
alice:1715680000:242
bob:1715681000:200
charlie:1715682000:158
EOF

    chown -R user:user /home/user
    chmod -R 777 /home/user
