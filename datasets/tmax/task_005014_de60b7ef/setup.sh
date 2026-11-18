#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user
    cat << 'EOF' > /home/user/db_graph.nt
<http://dbre/db/AuthDB> <http://dbre/dependsOn> <http://dbre/db/UserDB> .
<http://dbre/db/OrderDB> <http://dbre/dependsOn> <http://dbre/db/UserDB> .
<http://dbre/db/PaymentDB> <http://dbre/dependsOn> <http://dbre/db/OrderDB> .
<http://dbre/db/PaymentDB> <http://dbre/dependsOn> <http://dbre/db/UserDB> .
<http://dbre/db/ReportDB> <http://dbre/dependsOn> <http://dbre/db/OrderDB> .
<http://dbre/db/ReportDB> <http://dbre/dependsOn> <http://dbre/db/PaymentDB> .
<http://dbre/db/AuditDB> <http://dbre/dependsOn> <http://dbre/db/AuthDB> .
<http://dbre/db/AuditDB> <http://dbre/dependsOn> <http://dbre/db/PaymentDB> .

<http://dbre/db/UserDB> <http://dbre/lastBackupStatus> "SUCCESS" .
<http://dbre/db/AuthDB> <http://dbre/lastBackupStatus> "FAILED" .
<http://dbre/db/OrderDB> <http://dbre/lastBackupStatus> "SUCCESS" .
<http://dbre/db/PaymentDB> <http://dbre/lastBackupStatus> "MISSING" .
<http://dbre/db/ReportDB> <http://dbre/lastBackupStatus> "SUCCESS" .
<http://dbre/db/AuditDB> <http://dbre/lastBackupStatus> "FAILED" .

<http://dbre/db/UserDB> <http://dbre/dbSize> "50" .
<http://dbre/db/AuthDB> <http://dbre/dbSize> "10" .
<http://dbre/db/OrderDB> <http://dbre/dbSize> "100" .
<http://dbre/db/PaymentDB> <http://dbre/dbSize> "20" .
<http://dbre/db/ReportDB> <http://dbre/dbSize> "200" .
<http://dbre/db/AuditDB> <http://dbre/dbSize> "5" .
EOF

    chown -R user:user /home/user
    chmod -R 777 /home/user
