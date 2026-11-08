#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip wget build-essential
    pip3 install pytest

    # Download and vendor sqlite-autoconf
    mkdir -p /app
    cd /app
    wget https://sqlite.org/2023/sqlite-autoconf-3430100.tar.gz
    tar xzf sqlite-autoconf-3430100.tar.gz
    mv sqlite-autoconf-3430100 sqlite-autoconf
    rm sqlite-autoconf-3430100.tar.gz

    # Perturb Makefile.in
    sed -i 's/$(CC)/$(CC_BROKEN_TYPO)/g' /app/sqlite-autoconf/Makefile.in

    # Create oracle script
    mkdir -p /opt/oracle
    cat << 'EOF' > /opt/oracle/oracle_graph_join.sh
#!/bin/bash
/app/sqlite-autoconf/sqlite3 -csv -header "" "
.import '$1' nodes
.import '$2' edges
SELECT s.name AS source_name, t.name AS target_name, e.relation
FROM edges e
JOIN nodes s ON e.source_id = s.id
JOIN nodes t ON e.target_id = t.id
ORDER BY source_name ASC, target_name ASC, relation ASC;
"
EOF
    chmod +x /opt/oracle/oracle_graph_join.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
