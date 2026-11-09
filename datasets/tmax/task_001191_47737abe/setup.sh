#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/access.log
[2023-10-25T10:00:01Z] 10.0.0.5 POST /login HTTP/1.1 - Headers: {"X-Correlation-ID": "C001", "Cookie": "session_id=; attempt=1"}
[2023-10-25T10:00:05Z] 10.0.0.5 POST /login HTTP/1.1 - Headers: {"X-Correlation-ID": "C002", "Cookie": "session_id=; attempt=2"}
[2023-10-25T10:00:09Z] 10.0.0.5 POST /login HTTP/1.1 - Headers: {"X-Correlation-ID": "C003", "Cookie": "session_id=; attempt=3"}
[2023-10-25T10:05:00Z] 192.168.1.10 POST /login HTTP/1.1 - Headers: {"X-Correlation-ID": "C004", "Cookie": "session_id=alpha999; theme=dark"}
[2023-10-25T10:10:00Z] 172.16.0.2 POST /login HTTP/1.1 - Headers: {"X-Correlation-ID": "C005", "Cookie": "session_id=; attempt=1"}
[2023-10-25T10:11:00Z] 192.168.1.11 POST /login HTTP/1.1 - Headers: {"X-Correlation-ID": "C006", "Cookie": "session_id=beta888; lang=en"}
[2023-10-25T10:12:00Z] 10.0.0.5 POST /login HTTP/1.1 - Headers: {"X-Correlation-ID": "C007", "Cookie": "session_id=; attempt=4"}
[2023-10-25T10:13:00Z] 10.1.1.1 POST /login HTTP/1.1 - Headers: {"X-Correlation-ID": "C008", "Cookie": "lang=fr; session_id=gamma777"}
EOF

    cat << 'EOF' > /home/user/app.log
[2023-10-25T10:00:01Z] [WARN] [CorrID: C001] Event: LOGIN_FAILED User: admin
[2023-10-25T10:00:05Z] [WARN] [CorrID: C002] Event: LOGIN_FAILED User: admin
[2023-10-25T10:00:09Z] [WARN] [CorrID: C003] Event: LOGIN_FAILED User: admin
[2023-10-25T10:05:00Z] [INFO] [CorrID: C004] Event: LOGIN_SUCCESS User: alice
[2023-10-25T10:10:00Z] [WARN] [CorrID: C005] Event: LOGIN_FAILED User: bob
[2023-10-25T10:11:00Z] [INFO] [CorrID: C006] Event: LOGIN_SUCCESS User: charlie
[2023-10-25T10:12:00Z] [WARN] [CorrID: C007] Event: LOGIN_FAILED User: admin
[2023-10-25T10:13:00Z] [INFO] [CorrID: C008] Event: LOGIN_SUCCESS User: dave
EOF

    chmod -R 777 /home/user
