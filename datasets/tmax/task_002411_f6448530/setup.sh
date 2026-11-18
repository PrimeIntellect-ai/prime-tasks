#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/vendor_updates.log
[2023-10-24 10:00:00] LANG=fr-FR | KEY=ui.login | SRC=Login to your account | TGT=Connectez-vous à votre compte
[2023-10-24 10:05:00] LANG=fr-FR | KEY=ui.login | SRC=Login to your account | TGT=Connexion
[10/24/2023 10:10:00] LANG=fr-FR | KEY=ui.login | SRC=Login to your account | TGT=er
[2023-10-24 11:00:00] LANG=de-DE | KEY=ui.logout | SRC=Log out safely | TGT=Sicher abmelden
[2023-10-24 09:00:00] LANG=de-DE | KEY=ui.logout | SRC=Log out safely | TGT=Abmelden
[10/24/2023 12:00:00] LANG=es-ES | KEY=ui.error | SRC=An unexpected error occurred during the process | TGT=Na
[2023-10-24 11:50:00] LANG=es-ES | KEY=ui.error | SRC=An unexpected error occurred during the process | TGT=Ha ocurrido un error inesperado
[2023-10-24 13:00:00] LANG=es-ES | KEY=ui.error | SRC=An unexpected error occurred during the process | TGT=This string is extremely long and definitely a hallucination from the machine translation model that just keeps going and going and going and going and going and going and going and going and going and going and going
[10/25/2023 08:00:00] LANG=ja-JP | KEY=ui.welcome | SRC=Welcome! | TGT=ようこそ！
[2023-10-24 08:00:00] LANG=ja-JP | KEY=ui.welcome | SRC=Welcome! | TGT=歓迎
EOF

    chmod -R 777 /home/user
