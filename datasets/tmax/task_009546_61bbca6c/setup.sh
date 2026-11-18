#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /tmp/remote_loc/
    mkdir -p /home/user/

    cat << 'EOF' > /home/user/base_en.json
{
  "welcome_msg": "Welcome [ USER_NAME ], to [ App_Name ]!",
  "logout_btn": "Log out",
  "items_in_cart": "You have [ COUNT ] items.",
  "checkout": "Checkout now",
  "missing_translation": "This has no Spanish [ Variable ]"
}
EOF

    cat << 'EOF' > /tmp/remote_loc/es_updates.csv
key,translation
welcome_msg,¡Bienvenido [ USER_NAME ], a [ App_Name ]!
logout_btn,Cerrar sesión
items_in_cart,Tienes [ count ] artículos.
extra_key,No debería aparecer
EOF

    chmod -R 777 /home/user
    chmod -R 777 /tmp/remote_loc
