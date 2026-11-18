#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest pandas jinja2

mkdir -p /tmp/remote_l10n/
mkdir -p /home/user/workspace/

# Create the remote CSV
cat << 'EOF' > /tmp/remote_l10n/translations.csv
string_id,en,es,fr
greeting,Hello,Hola,Bonjour
farewell,Goodbye,Adiós,Au revoir
login,Log In,Iniciar sesión,Connexion
error_404,Not Found,No encontrado,Introuvable
EOF

# Create the Jinja2 template avoiding Apptainer build variable syntax
cat << 'EOF' > /home/user/workspace/strings.xml.j2
<?xml version="1.0" encoding="utf-8"?>
<resources>
{% for item in strings %}
    <string name="OPEN_BRACKET item.string_id CLOSE_BRACKET">OPEN_BRACKET item.value CLOSE_BRACKET</string>
{% endfor %}
</resources>
EOF

sed -i 's/OPEN_BRACKET/{{/g' /home/user/workspace/strings.xml.j2
sed -i 's/CLOSE_BRACKET/}}/g' /home/user/workspace/strings.xml.j2

useradd -m -s /bin/bash user || true
chown -R user:user /tmp/remote_l10n
chown -R user:user /home/user/workspace
chmod -R 777 /home/user
