#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip sqlite3 gawk
pip3 install pytest

mkdir -p /home/user/incoming/

sqlite3 /home/user/locales.db <<EOF
CREATE TABLE translations (locale TEXT, string_key TEXT, translation TEXT, PRIMARY KEY(locale, string_key));
INSERT INTO translations (locale, string_key, translation) VALUES ('jp', 'TITLE', '古いタイトル');
INSERT INTO translations (locale, string_key, translation) VALUES ('es', 'TITLE', 'Título');
INSERT INTO translations (locale, string_key, translation) VALUES ('es', 'OLD_KEY', 'Viejo');
EOF

cat <<'EOF' > /home/user/incoming/jp.tsv
TITLE	新しいタイトル
DESC	これは説明です
SUBMIT	送信
EOF

cat <<'EOF' > /home/user/incoming/es.tsv
TITLE	Nuevo Título
DESC	Esta es una descripción larga
SUBMIT	Enviar
DESC	Corta
A_KEY	Hola
Z_KEY	Fin
EOF

cat <<'EOF' > /home/user/incoming/fr.tsv
TITLE	Titre
DESC	Description
SUBMIT	Soumettre
EOF

cat <<'EOF' > /home/user/template.html
<!DOCTYPE html>
<html>
<head><title>__TITLE__</title></head>
<body>
    <h1>__TITLE__</h1>
    <p>__DESC__</p>
    <button>__SUBMIT__</button>
    <footer>__MISSING__</footer>
</body>
</html>
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
