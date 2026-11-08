#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip coreutils findutils bash
    pip3 install pytest

    # Objective 1: Vendored Doc Compiler
    mkdir -p /app/vendored/doc_compiler_v2.1/bin
    cat << 'EOF' > /app/vendored/doc_compiler_v2.1/bin/parser.sh
#!/bin/bash
TARGET_DIR="${1:-.}"
# Bug: -L causes find to follow symlinks blindly and hang on loops
find -L "${TARGET_DIR}" -type f -name "*.md"
EOF
    chmod +x /app/vendored/doc_compiler_v2.1/bin/parser.sh

    # Objective 2: Corpora Setup
    mkdir -p /home/user/corpora/clean
    mkdir -p /home/user/corpora/evil

    for i in $(seq -w 1 50); do
        # Clean directories with valid relative symlinks
        d="/home/user/corpora/clean/clean_$i"
        mkdir -p "$d/sub"
        echo "clean doc $i" > "$d/doc.md"
        echo "clean sub doc $i" > "$d/sub/subdoc.md"
        ln -s ../doc.md "$d/sub/link.md"

        # Evil directories with infinite symlink loops
        e="/home/user/corpora/evil/evil_$i"
        mkdir -p "$e/sub1" "$e/sub2"
        echo "evil doc $i" > "$e/doc.md"
        ln -s ../sub2 "$e/sub1/loop2"
        ln -s ../sub1 "$e/sub2/loop1"
    done

    # Objective 3: Sync requests log
    cat << 'EOF' > /home/user/sync_requests.log
SYNC_JOB: 101
PATH: /home/user/corpora/clean/clean_12
STATUS: PENDING
--
SYNC_JOB: 102
PATH: /home/user/corpora/evil/evil_33
STATUS: PENDING
--
SYNC_JOB: 103
PATH: /home/user/corpora/clean/clean_05
STATUS: PENDING
--
SYNC_JOB: 104
PATH: /home/user/corpora/evil/evil_01
STATUS: PENDING
--
EOF

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
