#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip tesseract-ocr tesseract-ocr-fra
pip3 install --default-timeout=100 pytest pytesseract Levenshtein Pillow pandas

mkdir -p /app

cat << 'EOF' > /app/reference_db.csv
key,english,french_expected
ERR_404,Not Found,Non trouvé
BTN_OK,OK,D'accord
BTN_CANCEL,Cancel,Annuler
MSG_WELCOME,Welcome,Bienvenue
LBL_USER,Username,Nom d'utilisateur
LBL_PASS,Password,Mot de passe
MSG_LOGOUT,Log out,Déconnexion
TXT_RETRY,Try again,Réessayer
EOF

python3 -c "
from PIL import Image, ImageDraw
text = '''ERR_404: Non trouve
BTN_OK: D'accor
BTN_CANCEL: Anuler
MSG_WELCOME: Bienvenue
LBL_USER: Nom d utilisateur
LBL_PASS: Mot de passe
MSG_LOGOUT: Deconnexion
TXT_RETRY: Reessayer'''
img = Image.new('RGB', (400, 300), color=(255, 255, 255))
d = ImageDraw.Draw(img)
d.text((10,10), text, fill=(0,0,0))
img.save('/app/ui_screenshot.png')
"

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user /app
