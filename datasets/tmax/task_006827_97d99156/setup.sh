#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip openssl
    pip3 install pytest pyjwt cryptography

    mkdir -p /home/user/certs /home/user/app

    # Generate CA
    openssl req -x509 -newkey rsa:2048 -days 365 -nodes -keyout /home/user/certs/ca.key -out /home/user/certs/ca.crt -subj "/C=US/O=MyOrg/CN=RootCA"

    # Generate Intermediate
    openssl req -newkey rsa:2048 -nodes -keyout /home/user/certs/intermediate.key -out /home/user/certs/intermediate.csr -subj "/C=US/O=MyOrg/CN=IntermediateCA"
    echo "basicConstraints=CA:TRUE" > /tmp/extfile.cnf
    openssl x509 -req -in /home/user/certs/intermediate.csr -CA /home/user/certs/ca.crt -CAkey /home/user/certs/ca.key -CAcreateserial -out /home/user/certs/intermediate.crt -days 365 -extfile /tmp/extfile.cnf

    # Generate Fake Intermediate
    openssl req -newkey rsa:2048 -nodes -keyout /home/user/certs/fake_int.key -out /home/user/certs/fake_int.crt -x509 -days 365 -subj "/C=US/O=MyOrg/CN=IntermediateCA"

    # Generate Candidate 1 (Invalid: signed by fake int)
    openssl req -newkey rsa:2048 -nodes -keyout /home/user/certs/cand1.key -out /home/user/certs/cand1.csr -subj "/C=US/O=MyOrg/CN=WRONG_SECRET_111"
    openssl x509 -req -in /home/user/certs/cand1.csr -CA /home/user/certs/fake_int.crt -CAkey /home/user/certs/fake_int.key -CAcreateserial -out /home/user/certs/candidate_1.crt -days 365

    # Generate Candidate 2 (Valid: signed by Intermediate)
    openssl req -newkey rsa:2048 -nodes -keyout /home/user/certs/cand2.key -out /home/user/certs/cand2.csr -subj "/C=US/O=MyOrg/CN=CORRECT_SECRET_999XYZ"
    openssl x509 -req -in /home/user/certs/cand2.csr -CA /home/user/certs/intermediate.crt -CAkey /home/user/certs/intermediate.key -CAcreateserial -out /home/user/certs/candidate_2.crt -days 365

    # Generate Candidate 3 (Invalid: Self-signed)
    openssl req -newkey rsa:2048 -nodes -keyout /home/user/certs/cand3.key -out /home/user/certs/candidate_3.crt -x509 -days 365 -subj "/C=US/O=MyOrg/CN=WRONG_SECRET_333"

    # Create log file
    cat << 'EOF' > /home/user/app/service.log
2023-10-01 12:00:00 INFO Service started
2023-10-01 12:05:00 DEBUG Using secret SUPER_SECRET_LEGACY_V1 for signing
2023-10-01 12:10:00 ERROR Failed validation for token eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyfQ.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c
2023-10-01 12:15:00 INFO User logged in with legacy secret SUPER_SECRET_LEGACY_V1
2023-10-01 12:20:00 DEBUG Processed request with eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.e30.another_fake_sig
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
