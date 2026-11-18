#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 procps
    pip3 install pytest

    mkdir -p /home/user/loc_workspace
    mkdir -p /home/user/server_root

    sqlite3 /home/user/loc_workspace/translations.db <<EOF
CREATE TABLE locales (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    en_source TEXT UNIQUE,
    es_target TEXT,
    fr_target TEXT
);
INSERT INTO locales (en_source, es_target, fr_target) VALUES ('Save changes', 'Guardar cambios', 'Enregistrer les modifications');
INSERT INTO locales (en_source, es_target, fr_target) VALUES ('Cancel operation', 'Cancelar', 'Annuler');
INSERT INTO locales (en_source, es_target, fr_target) VALUES ('Delete user account permanently', 'Eliminar cuenta de usuario permanentemente', 'Supprimer le compte');
EOF

    cat << 'EOF' > /home/user/server_root/new_strings.csv
en_source,es_target,fr_target
Save changes.,Guardar cambios.,Enregistrer les modifications.
Cancel operation,Cancelar la operación,Annuler l'opération
Welcome to the dashboard,Bienvenido al panel,Bienvenue sur le tableau de bord
Delete user accounts permanently,Eliminar cuentas de usuario permanentemente,Supprimer les comptes
EOF

    cat << 'EOF' > /home/user/server_root/translation_logs.csv
date,translator_id,word_count
2023-10-01,user1,500
2023-10-02,user1,300
2023-10-04,user1,600
2023-10-01,user2,100
2023-10-03,user2,250
2023-10-04,user2,150
EOF

    cd /home/user/server_root
    tar -czf updates.tar.gz new_strings.csv translation_logs.csv

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/start_server.sh
#!/bin/bash
if ! pgrep -f "python3 -m http.server 8080" > /dev/null; then
    nohup python3 -m http.server 8080 -d /home/user/server_root > /dev/null 2>&1 &
    sleep 1
fi
EOF
    chmod +x /home/user/start_server.sh

    chown -R user:user /home/user/loc_workspace
    chown -R user:user /home/user/server_root
    chmod -R 777 /home/user
