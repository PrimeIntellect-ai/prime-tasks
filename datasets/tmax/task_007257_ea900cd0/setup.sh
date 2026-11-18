#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip golang-go
pip3 install pytest

mkdir -p /home/user/loc_pipeline
cat << 'EOF' > /home/user/loc_pipeline/raw_translations.csv
timestamp,string_key,en,es,fr,ja,ar
2023-10-01T09:00:00Z,btn_submit,Submit,Enviar,,,
2023-10-01T10:00:00Z,btn_submit,,,,,إرسال
2023-10-01T08:00:00Z,btn_cancel,Cancel,Cancelar,Annuler,,
2023-10-01T09:30:00Z,btn_cancel,,,Annuler (updated),キャンセル,
2023-10-01T08:00:00Z,msg_welcome,,Bienvenido,,,
2023-10-01T09:00:00Z,msg_welcome,,,,ようこそ,
2023-10-01T11:00:00Z,lbl_user,User,,Utilisateur,,مستخدم
2023-10-01T10:00:00Z,lbl_user,User,Usuario,,,
2023-10-01T12:00:00Z,emoji_test,Hello 😊,,,,,
2023-10-01T12:05:00Z,emoji_test,,,Bonjour,,こんにちは 😊,
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
