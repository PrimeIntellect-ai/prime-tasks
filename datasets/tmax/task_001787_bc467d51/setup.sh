#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest

mkdir -p /app/polib-1.2.0
mkdir -p /home/user/loc_task

# Create the broken vendored package
cat << 'EOF' > /app/polib-1.2.0/setup.py
from setuptools import setup
setup(name='polib', version='1.2.0', py_modules=['polib'])
EOF

cat << 'EOF' > /app/polib-1.2.0/polib.py
class POEntry:
    def __init__(self, msgid="", msgstr=None): # BOGUS DEFAULT
        self.msgid = msgid
        self.msgstr = msgstr

class POFile(list):
    def percent_translated(self):
        translated = [e for e in self if e.msgstr and len(e.msgstr) > 0] # CRASHES HERE
        return len(translated) / len(self) * 100 if len(self) > 0 else 0

def pofile(path):
    po = POFile()
    with open(path, 'r', encoding='utf-8') as f:
        lines = f.readlines()
        entry = None
        for line in lines:
            if line.startswith('msgid '):
                entry = POEntry(msgid=line.split('"')[1])
                po.append(entry)
            elif line.startswith('msgstr '):
                if entry:
                    entry.msgstr = line.split('"')[1]
    return po
EOF

# Create the data files
cat << 'EOF' > /home/user/loc_task/es_ES.po
msgid "Welcome to our application"
msgstr "Bienvenido a nuestra aplicación"

msgid "Save your changes"
msgstr "Guarde sus cambios"

msgid "Delete user account"
msgstr "Eliminar cuenta de usuario"

msgid "Invalid password provided"
msgstr "Contraseña proporcionada no válida"
EOF

cat << 'EOF' > /home/user/loc_task/ui_strings.txt
2023-10-01 12:00:01 INFO UI_EVENT: "Welcome to our application"
2023-10-01 12:05:22 WARN UI_EVENT: "Save your change"
2023-10-01 12:10:14 ERROR UI_EVENT: "Invalid pasword provided"
2023-10-01 12:15:00 INFO UI_EVENT: "Logout completely"
EOF

# Create the ground truth reference
cat << 'EOF' > /home/user/loc_task/ground_truth.json
{
    "Welcome to our application": "Bienvenido a nuestra aplicación",
    "Save your change": "Guarde sus cambios",
    "Invalid pasword provided": "Contraseña proporcionada no válida",
    "Logout completely": null
}
EOF

chmod -R 777 /app
useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
