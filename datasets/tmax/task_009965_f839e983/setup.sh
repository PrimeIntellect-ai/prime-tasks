#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo rustc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/translations.jsonl
{"locale": "en-US", "key": "welcome", "text": "Welcome back, {user}!", "features": null}
{"locale": "en-US", "key": "farewell", "text": "Goodbye 👋", "features": null}
{"locale": "en-US", "key": "items", "text": "You have {count} items in your {container}.", "features": null}
{"locale": "fr-FR", "key": "welcome", "text": "Bon retour, {user}!", "features": null}
{"locale": "fr-FR", "key": "farewell", "text": null, "features": null}
{"locale": "ar-SA", "key": "welcome", "text": "مرحباً بعودتك يا {user}!", "features": null}
{"locale": "ar-SA", "key": "farewell", "text": "وداعا", "features": null}
{"locale": "ar-SA", "key": "items", "text": "", "features": null}
EOF

    chmod -R 777 /home/user
