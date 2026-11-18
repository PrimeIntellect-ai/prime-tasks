#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip rustc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/security.log
[2023-10-01T12:00:00] [CSP_VIOLATION] Blocked inline script execution.
[2023-10-01T12:01:00] [PAYLOAD_DELIVERY] Suspicious payload dropped in /tmp.
[2023-10-01T12:05:00] [SANDBOX_ESCAPE] Process isolated_worker escaped! Leaked token: AKIA-COMPROMISED-9988
[2023-10-01T12:06:00] [CERT_VALIDATION_FAILED] Untrusted root certificate.
EOF

    chmod -R 777 /home/user
