#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip sqlite3 cron
pip3 install pytest

mkdir -p /home/user/drops /home/user/processed

cat << 'EOF' > /home/user/base_en.json
{
  "welcome_msg": "Welcome, {name}! You have {count} new messages.",
  "logout_btn": "Log out",
  "error_not_found": "Error {code}: File {filename} not found."
}
EOF

cat << 'EOF' > /home/user/drops/es.json
{
  "welcome_msg": "¡Bienvenido, {name}! Tienes {count} mensajes nuevos.",
  "logout_btn": "Cerrar sesión",
  "error_not_found": "Error {code}: Archivo no encontrado." 
}
EOF

cat << 'EOF' > /home/user/drops/fr.json
{
  "welcome_msg": "Bienvenue, {name}!", 
  "logout_btn": "Se déconnecter",
  "error_not_found": "Erreur {code}: Fichier {filename} introuvable."
}
EOF

cat << 'EOF' > /home/user/drops/de.json
{
  "welcome_msg": "Willkommen, {name}! Sie haben {count} neue Nachrichten.",
  "logout_btn": "Abmelden",
  "error_not_found": "Fehler {code}: Datei {filename} nicht gefunden."
}
EOF

sqlite3 /home/user/loc_db.sqlite "CREATE TABLE translations (lang TEXT, key TEXT, text_val TEXT);"

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
