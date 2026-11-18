#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    sqlite3 /home/user/translations.db <<EOF
CREATE TABLE strings (
    id INTEGER PRIMARY KEY,
    lang TEXT,
    string_key TEXT,
    source_text TEXT,
    translated_text TEXT,
    updated_at TEXT
);
INSERT INTO strings (lang, string_key, source_text, translated_text, updated_at) VALUES 
('fr', 'welcome', 'Welcome %s to %s', 'Bienvenue %s à %s', '2023-01-01T00:00:00Z'),
('fr', 'goodbye', 'Goodbye', 'Au revoir', '2023-01-01T00:00:00Z'),
('es', 'welcome', 'Welcome %s to %s', 'Bienvenido %s a %s', '2023-01-01T00:00:00Z'),
('es', 'goodbye', 'Goodbye', 'Adios', '2023-01-01T00:00:00Z'),
('de', 'error', 'Error code: %s', 'Fehler: %s', '2023-01-01T00:00:00Z');
EOF

    cat << 'EOF' > /home/user/vendor_updates.csv
lang,string_key,translation,timestamp
fr,welcome, Salut %s vers %s ,2023-10-01T10:00:00Z
fr,welcome, Bonjour %s sur %s ,2023-10-02T10:00:00Z
es,welcome, Bienvenido a %s,2023-10-01T10:00:00Z
fr,goodbye,"",2023-10-01T10:00:00Z
it,welcome,Benvenuto %s,2023-10-01T10:00:00Z
de,error,Fehlercode %s,2023-10-01T10:00:00Z
EOF

    chmod -R 777 /home/user
