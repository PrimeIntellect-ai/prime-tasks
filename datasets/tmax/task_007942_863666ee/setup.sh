#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq gawk
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/l10n_input.csv
string_id,locale,translation,status
str_001,en-us,Hello world,approved
str_002,FR-fr,"Bonjour,
le monde",pending
str_003,es-es,Hola,rejected
str_004,PT-BR,,approved
str_005,de-de,Ein sehr langes Wort das eigentlich ein Satz ist und mehr als zwanzig Worte enthält um die Anomalieerkennung zu triggern eins zwei drei vier fünf sechs sieben acht neun zehn elf zwölf dreizehn vierzehn fünfzehn sechzehn siebzehn achtzehn neunzehn zwanzig einundzwanzig,approved
str_006,It-it,"Ciao, multi
line
test",approved
EOF

    chmod -R 777 /home/user
