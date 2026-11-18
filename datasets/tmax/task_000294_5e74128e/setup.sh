#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tar
    pip3 install pytest

    mkdir -p /home/user/setup_tmp
    cd /home/user/setup_tmp

    # 1. Create rules.ini
    cat << 'EOF' > rules.ini
[Output]
extensions=.md,.txt

[Tools]
format=ELF
EOF

    # 2. Create backup.log with multi-line entries
    cat << 'EOF' > backup.log
[2023-10-14 08:12:01] INFO Backup started.
[2023-10-14 08:12:05] ERROR Incident ID: 11029
Traceback (most recent call last):
  File "main.py", line 12, in <module>
TimeoutError: Connection lost
[2023-10-14 08:15:22] ERROR Incident ID: 88310
Traceback (most recent call last):
  File "archiver.py", line 105, in traverse
InfiniteSymlinkException: Symlink loop detected at depth 256
[2023-10-14 08:16:00] INFO Retry scheduled.
EOF

    # 3. Create docs_a with a symlink loop and markdown files
    mkdir -p docs_a/content
    echo "# Introduction" > docs_a/intro.md
    echo "Setup instructions" > docs_a/content/setup.md
    cd docs_a
    ln -s . loop_dir
    cd ..
    tar -czf docs_a.tar.gz docs_a

    # 4. Create docs_b with text files and an ELF binary
    mkdir -p docs_b/api
    echo "API reference" > docs_b/api/api.txt
    cp /bin/ls docs_b/doc_generator
    cd docs_b
    ln -s ../docs_a evil_link
    cd ..
    tar -czf docs_b.tar.gz docs_b

    # 5. Package into the master archive
    tar -cf /home/user/raw_data.tar rules.ini backup.log docs_a.tar.gz docs_b.tar.gz

    # 6. Clean up setup files
    cd /home/user
    rm -rf /home/user/setup_tmp

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
