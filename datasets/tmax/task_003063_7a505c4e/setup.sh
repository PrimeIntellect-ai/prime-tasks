#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /app/loctool-1.0.0/loctool
    touch /app/loctool-1.0.0/loctool/__init__.py

    cat << 'EOF' > /app/loctool-1.0.0/loctool/extractor.py
import os

class Extractor:
    def __init__(self):
        self.records = []

    def extract(self, data):
        retries = 3
        for attempt in range(retries):
            try:
                for k, v in data.items():
                    self.records.append({"key": k, "value": v})
                    if os.environ.get("SIMULATE_FLAKE") == "1" and attempt == 0 and len(self.records) == 1:
                        raise Exception("Transient flake")
                return self.records
            except Exception as e:
                if attempt == retries - 1:
                    raise
                # Bug: self.records is not cleared before retrying
EOF

    mkdir -p /app/corpora/clean /app/corpora/evil

    cat << 'EOF' > /app/corpora/source.json
{
  "welcome": "Welcome {name} to {app_name}!",
  "logout": "Logout",
  "items_in_cart": "You have {count} items in your cart."
}
EOF

    cat << 'EOF' > /app/corpora/clean/es.json
{
  "welcome": "¡Bienvenido {name} a {app_name}!",
  "logout": "Cerrar sesión",
  "items_in_cart": "Tienes {count} artículos en tu carrito."
}
EOF

    cat << 'EOF' > /app/corpora/clean/fr.json
{
  "welcome": "Bienvenue {name} sur {app_name}!",
  "logout": "Déconnexion",
  "items_in_cart": "Vous avez {count} articles dans votre panier."
}
EOF

    cat << 'EOF' > /app/corpora/evil/missing_key.json
{
  "welcome": "Welcome {name} to {app_name}!",
  "logout": "Logout"
}
EOF

    cat << 'EOF' > /app/corpora/evil/extra_key.json
{
  "welcome": "Welcome {name} to {app_name}!",
  "logout": "Logout",
  "items_in_cart": "You have {count} items in your cart.",
  "new_key": "Hello"
}
EOF

    cat << 'EOF' > /app/corpora/evil/bad_placeholder.json
{
  "welcome": "Welcome {nombre} to {app_name}!",
  "logout": "Logout",
  "items_in_cart": "You have {count} items in your cart."
}
EOF

    cat << 'EOF' > /app/corpora/evil/missing_placeholder.json
{
  "welcome": "Welcome to {app_name}!",
  "logout": "Logout",
  "items_in_cart": "You have {count} items in your cart."
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
