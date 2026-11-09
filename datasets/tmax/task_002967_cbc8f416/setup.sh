#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk sed grep bash coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/translations.csv
string_id,locale,translation,translator_email
btn_ok,fr,D'accord,alice@example.com
msg_welcome,es,"Hola,
bienvenido a nuestra app.",bob123@translation.corp
err_404,de,"Nicht gefunden.
Bitte versuchen Sie es erneut.",charlie.d@freelance.org
lbl_profile,ja,"プロフィール",dave@tokyo.jp
msg_quote,en,"It's a ""quote""",eve@test.com
EOF

    chmod -R 777 /home/user
