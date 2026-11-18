#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk locales
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/generate_input.py
# coding: utf-8
csv_content = """key,en,fr,de,es
greeting,Hello,Bonjour,Hallo,Hola
goodbye,Goodbye,Au revoir,Auf Wiedersehen,Adiós
error_1,An unexpected error occurred.,Une erreur inattendue s'est produite.,Ein unerwarteter Fehler ist aufgetreten.,Un error inesperado ha ocurrido.
short_test,Yes,Oui,Ja,Sí
anomaly_test,This is a normal sentence.,C'est une phrase normale.,Dies ist ein normaler Satz.,X
long_anomaly,Short,Ceci est une traduction française extrêmement longue qui ne correspond pas du tout au texte d'origine.,Kurz,Corto
btn_ok,OK,OK,OK,OK
btn_cancel,Cancel,Annuler,Abbrechen,Cancelar"""

with open("/home/user/translations.csv", "w", encoding="iso-8859-1") as f:
    f.write(csv_content)
EOF
    python3 /home/user/generate_input.py
    rm /home/user/generate_input.py

    chmod -R 777 /home/user
