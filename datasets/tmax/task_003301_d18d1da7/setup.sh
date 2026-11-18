#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq cron
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/logs

    cat << 'EOF' > /home/user/logs/app.jsonl
{"level": "INFO", "message": "The quick\u0020brown fox jumps over the lazy dog."}
{"level": "ERROR", "message": "System\u00A0error: \u201Cdatabase connection failed\u201D!"}
{"level": "WARN", "message": "Retrying... success."}
{"level": "DEBUG", "message": "User\u0020login\u00A0attempt\u0020number\u0020forty\u0020two."}
EOF

    cat << 'EOF' > /home/user/expected_sampled_tokens.txt
brown
over
dog
database
retrying
login
forty
EOF

    chown -R user:user /home/user/logs /home/user/expected_sampled_tokens.txt
    chmod -R 777 /home/user
