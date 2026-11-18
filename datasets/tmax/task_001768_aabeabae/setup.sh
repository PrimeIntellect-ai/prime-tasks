#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go sqlite3
    pip3 install pytest

    mkdir -p /home/user
    sqlite3 /home/user/loc_data.db <<EOF
CREATE TABLE reviews (id INTEGER PRIMARY KEY, locale TEXT, category TEXT, user_email TEXT, review_text TEXT);
INSERT INTO reviews VALUES (1, 'en-US', 'UI', 'alice@foo.com', 'Great UI');
INSERT INTO reviews VALUES (2, 'en-US', 'UI', 'bob@bar.com', 'Needs work');
INSERT INTO reviews VALUES (3, 'en-US', 'UI', 'charlie@baz.com', 'Okay I guess');
INSERT INTO reviews VALUES (4, 'en-US', 'UI', 'dave@qux.com', 'Terrible UI');
INSERT INTO reviews VALUES (5, 'fr-FR', 'Docs', 'pierre@paris.fr', 'Bonjour, good docs');
INSERT INTO reviews VALUES (6, 'fr-FR', 'Docs', 'marie@lyon.fr', 'Merci pour le guide');
INSERT INTO reviews VALUES (7, 'es-ES', 'UI', 'juan@madrid.es', 'Hola, UI is nice');
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
