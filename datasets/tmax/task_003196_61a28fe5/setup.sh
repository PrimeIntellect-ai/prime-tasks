#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas

    mkdir -p /home/user

    # Create translations.csv with embedded newlines
    cat << 'EOF' > /home/user/translations.csv
string_id,locale,translation_text
btn_save,en_US,Save
btn_save,es_ES,"Guardar
Archivo"
btn_save,ja_JP,保存
btn_cancel,en_US,Cancel
btn_cancel,es_ES,"Cancelar,
y salir"
hdr_welcome,en_US,"Welcome, User"
hdr_welcome,de_DE,"Willkommen
Benutzer"
EOF

    # Create metrics.csv
    cat << 'EOF' > /home/user/metrics.csv
timestamp,string_id,locale,clicks
2023-10-01T08:15:00Z,btn_save,en_US,15
2023-10-01T09:22:00Z,btn_save,es_ES,10
2023-10-01T10:05:00Z,btn_save,ja_JP,5
2023-10-01T11:00:00Z,btn_cancel,en_US,2
2023-10-01T11:30:00Z,btn_cancel,es_ES,-5
2023-10-01T14:00:00Z,hdr_welcome,de_DE,20
2023-10-02T08:00:00Z,btn_save,en_US,18
2023-10-02T09:00:00Z,btn_save,es_ES,12
2023-10-02T10:00:00Z,btn_cancel,en_US,4
2023-10-02T11:00:00Z,btn_cancel,es_ES,8
2023-10-02T12:00:00Z,invalid_str,en_US,100
2023-10-03T07:00:00Z,hdr_welcome,en_US,50
2023-10-03T08:00:00Z,hdr_welcome,de_DE,45
2023-10-03T09:00:00Z,btn_save,ja_JP,15
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
