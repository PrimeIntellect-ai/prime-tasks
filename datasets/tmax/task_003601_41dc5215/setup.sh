#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 ffmpeg espeak
    pip3 install pytest

    mkdir -p /app
    mkdir -p /home/user

    # Generate the voicemail audio
    espeak -w /app/alert_voicemail.wav "Node backup-server-delta has failed."

    # Create the SQLite database
    sqlite3 /home/user/backup_topology.db <<EOF
CREATE TABLE backup_dependencies (source_node TEXT, target_node TEXT);
INSERT INTO backup_dependencies VALUES ('backup-server-alpha', 'backup-server-beta');
INSERT INTO backup_dependencies VALUES ('backup-server-beta', 'backup-server-gamma');
INSERT INTO backup_dependencies VALUES ('backup-server-delta', 'backup-server-epsilon');
INSERT INTO backup_dependencies VALUES ('backup-server-epsilon', 'backup-server-zeta');
INSERT INTO backup_dependencies VALUES ('backup-server-delta', 'backup-server-eta');
EOF

    # Create the oracle script
    cat << 'EOF' > /app/oracle_impact_analysis.sh
#!/bin/bash
sqlite3 /home/user/backup_topology.db "
WITH RECURSIVE affected(node) AS (
    SELECT '$1'
    UNION
    SELECT target_node FROM backup_dependencies, affected
    WHERE backup_dependencies.source_node = affected.node
)
SELECT node FROM affected ORDER BY node;
"
EOF
    chmod +x /app/oracle_impact_analysis.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
