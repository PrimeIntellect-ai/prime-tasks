#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils tar
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /app /home/user/docs_backup /home/user/quarantine /home/user/extracted_docs

    # 1. Create the stripped binary /app/doc_indexer
    cat << 'EOF' > /tmp/indexer.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char *argv[]) {
    if (argc != 3 || strcmp(argv[1], "--build") != 0) {
        printf("Usage: doc_indexer --build <target_dir>\n");
        return 1;
    }
    FILE *f = fopen("index.dat", "wb");
    if (!f) return 1;
    fprintf(f, "MAGIC_INDEX_V1\n");
    fprintf(f, "DIR:%s\n", argv[2]);
    fclose(f);
    printf("Created index.dat\n");
    return 0;
}
EOF
    gcc -O2 /tmp/indexer.c -o /app/doc_indexer
    strip /app/doc_indexer
    rm /tmp/indexer.c

    # 2. Create incremental backups
    mkdir -p /tmp/backups/docs
    echo "Base doc" > /tmp/backups/docs/intro.txt
    echo "<html>Old html</html>" > /tmp/backups/docs/old.HTM
    tar -cf /home/user/docs_backup/backup_0.tar -C /tmp/backups docs/

    # Incremental update
    echo "New doc" > /tmp/backups/docs/new.txt
    tar -cf /home/user/docs_backup/backup_1.tar -C /tmp/backups docs/new.txt

    # Malicious zip-slip backup
    mkdir -p /tmp/bad
    echo "Pwned" > /tmp/bad/pwn.txt
    tar -cf /home/user/docs_backup/backup_2.tar -C /tmp/bad pwn.txt
    # Manually inject malicious path using python
    python3 -c "
import tarfile
with tarfile.open('/home/user/docs_backup/backup_2.tar', 'w') as t:
    ti = tarfile.TarInfo('../../../etc/pwned')
    ti.size = 5
    with open('/tmp/bad/pwn.txt', 'rb') as f:
        t.addfile(ti, f)
"

    # Final incremental backup
    echo "Final doc" > /tmp/backups/docs/final.txt
    echo "Corrupted doc" > /tmp/backups/docs/bad_doc.txt
    tar -cf /home/user/docs_backup/backup_3.tar -C /tmp/backups docs/final.txt docs/bad_doc.txt

    # 3. Create the log file
    cat << 'EOF' > /home/user/migration.log
[INFO]
DocID: 1000
Reason: Migrated
File: intro.txt
---
[ERROR]
DocID: 1045
Reason: Corrupted metadata
File: bad_doc.txt
---
[INFO]
DocID: 1046
Reason: Migrated
File: final.txt
---
EOF

    chown -R user:user /home/user/docs_backup /home/user/quarantine /home/user/extracted_docs /home/user/migration.log
    chmod -R 777 /home/user
