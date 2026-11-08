#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo build-essential
    pip3 install pytest

    # Create the user
    useradd -m -s /bin/bash user || true

    # Create the input file
    cat << 'EOF' > /home/user/raw_translations.jsonl
{"id": "m1", "locale": "es_ES", "content": "El resultado de $ 2 + 2 $ es 4."}
{"id": "m2", "locale": "es_ES", "content": "Calcular $x = y * ( z - 1 ) / 2$"}
{"id": "m3", "locale": "fr_FR", "content": "L'équation $E = m * c^2$ est célèbre."}
{"id": "m4", "locale": "fr_FR", "content": "Sans maths ici."}
{"id": "m5", "locale": "en_US", "content": "Let $ f(x) = x^2 - 4 * x + 4 $ and $ y = 0 $"}
EOF

    # Set permissions
    chmod -R 777 /home/user
