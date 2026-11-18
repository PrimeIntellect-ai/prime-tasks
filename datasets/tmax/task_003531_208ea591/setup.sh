#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install --default-timeout=100 pytest pandas

    mkdir -p /home/user/logs /home/user/loc /home/user/templates

    cat << 'EOF' > /home/user/logs/ui_events.csv
timestamp,user_id,element_id
2023-10-13 10:00:00,u1,btn_home
2023-10-13 10:05:00,u2,btn_home
2023-10-13 11:00:00,u1,btn_settings
2023-10-13 11:00:00,u1,btn_settings
2023-10-14 09:00:00,u3,btn_profile
2023-10-14 09:10:00,u4,btn_profile
2023-10-14 09:20:00,u5,btn_profile
2023-10-15 08:00:00,u1,btn_home
2023-10-15 08:15:00,u2,btn_home
2023-10-15 08:30:00,u3,btn_home
2023-10-15 08:45:00,u4,btn_home
2023-10-15 09:00:00,u1,btn_profile
2023-10-15 09:05:00,u1,btn_profile
,u2,btn_profile
2023-10-15 10:00:00,u3,
EOF

    cat << 'EOF' > /home/user/loc/mapping.json
{
    "btn_home": "LOC_HOME_TITLE",
    "btn_settings": "LOC_SETTINGS_MAIN",
    "btn_profile": "LOC_PROFILE_VIEW"
}
EOF

    cat << 'EOF' > /home/user/templates/request_template.txt
# Translation Update Request

Please prioritize translations for the following high-traffic keys:
{KEYS}

Thank you!
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
