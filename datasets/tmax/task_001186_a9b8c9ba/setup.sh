#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk coreutils libc-bin
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/translations

    # Create English source (UTF-8)
    cat << 'EOF' > /home/user/translations/en.csv
BTN_OK,OK
BTN_CANCEL,Cancel
MSG_WELCOME,Welcome to our app
MSG_ERROR,An error occurred
EOF

    # Create French source (ISO-8859-1)
    cat << 'EOF' | iconv -f UTF-8 -t ISO-8859-1 > /home/user/translations/fr.csv
BTN_OK,D'accord
BTN_CANCEL,Annuler
MSG_WELCOME,Bienvenue dans l'app
MSG_ERROR,Une erreur inattendue et tres grave
EOF

    # Create Japanese source (UTF-16LE)
    cat << 'EOF' | iconv -f UTF-8 -t UTF-16LE > /home/user/translations/jp.csv
BTN_OK,承知いたしました
BTN_CANCEL,キャンセル
MSG_WELCOME,ようこそ
MSG_ERROR,エラー
EOF

    chmod -R 777 /home/user
