#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl tar

    pip3 install pytest

    mkdir -p /app/vendor
    cd /app/vendor
    curl -sL https://github.com/RDFLib/rdflib/archive/refs/tags/6.2.0.tar.gz | tar -xz
    mv rdflib-6.2.0 rdflib

    # Inject perturbations
    sed -i '1i import missing_sys_module_xyz_broken' /app/vendor/rdflib/rdflib/__init__.py

    # Inject into setup.py install_requires
    sed -i 's/install_requires=\[/install_requires=\["missing_sys_module_xyz_broken",/' /app/vendor/rdflib/setup.py
    # If the above sed didn't work because of formatting, just append it or replace a known string
    sed -i 's/"isodate/"missing_sys_module_xyz_broken",\n        "isodate/' /app/vendor/rdflib/setup.py

    # Create user and directories
    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/corpora/clean
    mkdir -p /home/user/corpora/evil

    # Populate clean1.ttl (A -> B -> C, C is Full, A, B are Diff)
    cat << 'EOF' > /home/user/corpora/clean/clean1.ttl
@prefix db: <http://example.org/db/> .

db:C a db:Backup ;
    db:backupType "Full" .

db:B a db:Backup ;
    db:backupType "Differential" ;
    db:dependsOn db:C .

db:A a db:Backup ;
    db:backupType "Differential" ;
    db:dependsOn db:B .
EOF

    # Populate evil1.ttl (A -> B -> A, Circular)
    cat << 'EOF' > /home/user/corpora/evil/evil1.ttl
@prefix db: <http://example.org/db/> .

db:A a db:Backup ;
    db:backupType "Differential" ;
    db:dependsOn db:B .

db:B a db:Backup ;
    db:backupType "Differential" ;
    db:dependsOn db:A .
EOF

    # Populate evil2.ttl (A -> B -> missing, Orphaned Diff)
    cat << 'EOF' > /home/user/corpora/evil/evil2.ttl
@prefix db: <http://example.org/db/> .

db:A a db:Backup ;
    db:backupType "Differential" ;
    db:dependsOn db:B .

db:B a db:Backup ;
    db:backupType "Differential" ;
    db:dependsOn db:Missing .
EOF

    chmod -R 777 /home/user
    chmod -R 777 /app/vendor
