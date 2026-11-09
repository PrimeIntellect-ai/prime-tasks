#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip golang sqlite3
pip3 install pytest

mkdir -p /home/user

# Create the CSV file using Python to avoid Apptainer build variable parsing issues with double curly braces
python3 -c '
with open("/home/user/raw_translations.csv", "w", encoding="utf-8") as f:
    f.write("key,lang,translation\n")
    f.write("greeting_msg,en,\"Hello {name},   welcome to   the system!\"\n")
    f.write("error_404,fr,\"Page non trouvée pour [url]   \"\n")
    f.write("checkout_item,es,\"  Item " + chr(123) + chr(123) + "item_id" + chr(125) + chr(125) + " añadido  a la cesta.\"\n")
    f.write("promo_code,de,\"  Der Code [PROMO_123] ist ungültig für {user_type}.\"\n")
'

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
