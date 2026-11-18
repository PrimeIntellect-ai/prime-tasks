#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Install Go and SQLite3
    apt-get install -y golang sqlite3

    # Create the translations.csv file
    mkdir -p /home/user
    cat << 'EOF' > /home/user/translations.csv
id,english,translated
row1,"Hello World","Bonjour le monde"
row2,"Save","Save"
row3,"Multiline
Text","Texte
Multiligne"
row4,"User","User"
row5,"Settings","Paramètres"
row6,"Okay","Okey"
row7,"A long text with
newlines
and stuff","Un long texte avec
des retours à la ligne
et des choses"
EOF

    # Create user and adjust permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
