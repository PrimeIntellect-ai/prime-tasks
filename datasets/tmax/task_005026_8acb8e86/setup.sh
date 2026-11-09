#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg
    pip3 install pytest

    mkdir -p /app
    mkdir -p /home/user

    # Create the video fixture
    ffmpeg -y -f lavfi -i color=c=red:s=640x480:d=4.5 \
           -f lavfi -i color=c=green:s=640x480:d=4.7 \
           -f lavfi -i color=c=blue:s=640x480:d=4.8 \
           -f lavfi -i color=c=yellow:s=640x480:d=6.0 \
           -filter_complex "[0:v][1:v][2:v][3:v]concat=n=4:v=1:a=0[v]" \
           -map "[v]" /app/ui_walkthrough.mp4

    # Create the data files
    cat << 'EOF' > /home/user/locales_old.json
{
  "ui_welcome": {"en": "Welcome", "fr": "Bienvenue", "es": "Bienvenido "},
  "ui_dashboard": {"en": "Dashboard"},
  "ui_settings": {"en": "Settings", "de": "Einstellungen"},
  "ui_logout": {"en": "Log out", "es": "Cerrar"}
}
EOF

    cat << 'EOF' > /home/user/updates.csv
key,lang,text
ui_welcome,es,Bienvenido
ui_logout,fr,Se déconnecter
ui_logout,es,Cerrar sesión
EOF

    cat << 'EOF' > /home/user/vendor_translations.xml
<translations>
  <item key="ui_dashboard" lang="de">Instrumententafel</item>
  <item key="ui_dashboard" lang="fr">Tableau de bord</item>
  <item key="ui_settings" lang="fr">Paramètres</item>
</translations>
EOF

    cat << 'EOF' > /home/user/sequence.txt
ui_welcome
ui_dashboard
ui_settings
ui_logout
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
