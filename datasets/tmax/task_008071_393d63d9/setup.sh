#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/master_en.json
{
  "welcome_message": "Welcome!",
  "login_button": "Log In",
  "error_404": "Page not found.",
  "footer_text": "Copyright 2023.",
  "checkout_cart": "Checkout",
  "promo_code": "Enter Promo"
}
EOF

    cat << 'EOF' > /home/user/incoming_fr.json
{
  "Welcome Message": "Bienvenue!",
  "LOGIN_button": "Connexion (Veuillez noter que si vous avez oublie votre mot de passe, vous devez contacter l'administrateur du systeme immediatement pour recuperer votre acces au portail web principal. Merci de votre comprehension.)",
  "error_404": "Page non trouvee.",
  "checkout cart": "Caisse",
  "extra_vendor_key": "Ignorer"
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
