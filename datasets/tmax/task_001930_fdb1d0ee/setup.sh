#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 bash coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user

    sqlite3 /home/user/backup_meta.db <<EOF
CREATE TABLE servers (id INTEGER PRIMARY KEY, hostname TEXT);
CREATE TABLE network_links (source_id INTEGER, dest_id INTEGER, latency INTEGER);
CREATE TABLE backups (id INTEGER PRIMARY KEY, server_id INTEGER, db_name TEXT);

INSERT INTO servers (id, hostname) VALUES 
(1, 'backup-01'), 
(2, 'relay-01'), 
(3, 'relay-02'), 
(4, 'db-target-01'), 
(5, 'archive-01');

INSERT INTO network_links (source_id, dest_id, latency) VALUES
(1, 2, 10),
(1, 3, 20),
(2, 3, 5),
(2, 4, 50),
(3, 4, 15),
(5, 1, 5);

INSERT INTO backups (id, server_id, db_name) VALUES
(100, 1, 'main_prod'),
(101, 5, 'old_logs');
EOF

    cat << 'EOF' > /home/user/get_links.sh
#!/bin/bash
# Buggy query with missing join condition causing implicit cross join
sqlite3 /home/user/backup_meta.db "SELECT s1.hostname, s2.hostname, nl.latency FROM servers s1, servers s2, network_links nl WHERE s1.id = nl.source_id;"
EOF
    chmod +x /home/user/get_links.sh

    chown -R user:user /home/user
    chmod -R 777 /home/user
