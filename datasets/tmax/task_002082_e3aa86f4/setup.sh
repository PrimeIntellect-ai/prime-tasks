#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo rustc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/inputs
    mkdir -p /home/user/temp

    # US - UTF-8
    cat << 'EOF' > /home/user/inputs/us_feedback.csv
12/31/2023 04:30:00 PM,login_btn,Login is confusing
01/01/2024 09:15:00 AM,logout_btn,Works well
EOF

    # DE - ISO-8859-1
    printf "31.12.2023 22:00:00,login_btn,Anmelden ist verwirrend\n01.01.2024 10:00:00,logout_btn,Funktioniert gut\n" | iconv -f UTF-8 -t ISO-8859-1 > /home/user/inputs/de_feedback.csv

    # JP - Shift_JIS
    printf "2024/01/01 07:00:00,login_btn,ログインがわかりにくい\n2024/01/01 18:30:00,logout_btn,よく機能する\n" | iconv -f UTF-8 -t Shift_JIS > /home/user/inputs/jp_feedback.csv

    chmod -R 777 /home/user
