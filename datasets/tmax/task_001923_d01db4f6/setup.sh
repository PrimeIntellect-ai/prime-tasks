#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/untranslated.txt
ERR_FILE_NOT_FOUND="File not found"
INVALID_LINE_NO_QUOTES=Welcome to the system
MSG_WELCOME="Welcome to the system"
BTN_SUBMIT="Submit form"
EOF

    cat << 'EOF' > /home/user/tm.tsv
File is not found	El archivo no se encuentra
File cannot be found	No se puede encontrar el archivo
Welcome to our system	Bienvenido a nuestro sistema
Welcome to system	Bienvenido al sistema
Submit your form	Envíe su formulario
Submit the form	Enviar el formulario
EOF

    chown user:user /home/user/untranslated.txt /home/user/tm.tsv
    chmod -R 777 /home/user
