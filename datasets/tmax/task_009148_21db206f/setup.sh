#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/inputs

    cat << 'EOF' > /home/user/inputs/server_eu.jsonl
{"time_local": "2023-10-25 14:30:00+02:00", "contact_email": "alice@test.com", "ip_address": "192.168.1.10", "suggested_translation": "Contact me at alice@test.com for the file."}
{"time_local": "2023-10-25 16:45:00+02:00", "contact_email": "bob@test.com", "ip_address": "10.0.0.5", "suggested_translation": "The quick brown fox jumps over 192.168.1.100."}
EOF

    cat << 'EOF' > /home/user/inputs/server_us.csv
epoch_time,user_ip,suggested_translation
1698235200,8.8.8.8,Please send the info to charlie@domain.org quickly.
1698253200,1.1.1.1,The swift brown fox leaps.
EOF

    cat << 'EOF' > /home/user/inputs/tm_references.json
{
  "ref1": "Contact me at [EMAIL] for the file.",
  "ref2": "The quick brown fox jumps over [IP].",
  "ref3": "Please send the info to [EMAIL] quickly.",
  "ref4": "The swift brown fox leaps."
}
EOF

    chmod -R 777 /home/user
