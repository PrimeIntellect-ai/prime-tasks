#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas

    mkdir -p /home/user/localization_data

    cat << 'EOF' > /home/user/localization_data/strings.csv
string_id,language_code,original_text,translated_text
s1,es,Hello,Hola
s2,zh,World,世界
s3,ar,Test,اختبار
s4,ja,Apple,りんご
s5,ru,Car,Машина
s6,ko,Computer,컴퓨터
s7,de,Window,Fenster
EOF

    cat << 'EOF' > /home/user/localization_data/telemetry.csv
timestamp,string_id,translator_id,edit_distance
2023-10-01T10:00:00Z,s1,t1,1
2023-10-01T10:05:00Z,s2,t1,
2023-10-01T10:10:00Z,s3,t1,3
2023-10-01T10:15:00Z,s4,t1,2
2023-10-01T10:20:00Z,s5,t1,6
2023-10-01T09:00:00Z,s6,t2,
2023-10-01T09:05:00Z,s7,t2,1
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
