#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip sqlite3 cron
pip3 install pytest

mkdir -p /home/user/locales
mkdir -p /home/user/output

cat << 'EOF' > /tmp/setup_files.py
ja_text = "こんにちは\n世界"
de_text = "Grüße\nÜberraschung"
ru_text = "Привет\nМир"

with open('/home/user/locales/ja.txt', 'w', encoding='shift_jis') as f:
    f.write(ja_text)

with open('/home/user/locales/de.txt', 'w', encoding='iso-8859-1') as f:
    f.write(de_text)

with open('/home/user/locales/ru.txt', 'w', encoding='koi8-r') as f:
    f.write(ru_text)

template = """<html>
<head><meta charset="UTF-8"></head>
<body>
    <h1>{T}</h1>
    <p>{C}</p>
</body>
</html>""".replace("{T}", "{" + "{TITLE}" + "}").replace("{C}", "{" + "{CONTENT}" + "}")

with open('/home/user/template.html', 'w', encoding='utf-8') as f:
    f.write(template)
EOF

python3 /tmp/setup_files.py

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
