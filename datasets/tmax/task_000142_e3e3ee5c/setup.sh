#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq zip unzip tar make
    pip3 install pytest

    # Create vendored package directory
    mkdir -p /app/vendored/doc-unpack-1.2.0/bin

    # Create unpack.sh
    cat << 'EOF' > /app/vendored/doc-unpack-1.2.0/bin/unpack.sh
#!/bin/bash
export UNPACK_BIN=/bin/false
ARCHIVE=$1
OUTDIR=$2
mkdir -p "$OUTDIR"
$UNPACK_BIN -xzf "$ARCHIVE" -C "$OUTDIR" || true
find "$OUTDIR" -name "*.zip" -exec unzip -q -o {} -d "$OUTDIR" \;
EOF
    chmod +x /app/vendored/doc-unpack-1.2.0/bin/unpack.sh

    # Create Makefile with spaces instead of tabs
    cat << 'EOF' > /app/vendored/doc-unpack-1.2.0/Makefile
install:
    cp bin/unpack.sh /usr/local/bin/doc-unpack
    chmod +x /usr/local/bin/doc-unpack
EOF

    # Create corpora directories
    mkdir -p /app/corpora/clean /app/corpora/evil

    # Generate Clean Corpus
    mkdir -p /tmp/clean1
    echo '{"valid": true}' > /tmp/clean1/metadata.json
    echo 'Author: John Doe' > /tmp/clean1/changelog.log
    echo '# Readme' > /tmp/clean1/readme.md
    chmod 644 /tmp/clean1/readme.md
    cd /tmp/clean1 && zip -q inner.zip metadata.json changelog.log readme.md
    cd /tmp/clean1 && tar -czf /app/corpora/clean/clean1.tar.gz inner.zip

    # Generate Evil Corpus
    # 1. symlink_bomb.tar.gz
    mkdir -p /tmp/evil1
    ln -s /etc/passwd /tmp/evil1/passwd_link
    cd /tmp/evil1 && tar -czf /app/corpora/evil/symlink_bomb.tar.gz passwd_link

    # 2. exec_md.tar.gz
    mkdir -p /tmp/evil2
    echo '# Executable' > /tmp/evil2/readme.md
    chmod +x /tmp/evil2/readme.md
    cd /tmp/evil2 && tar -czf /app/corpora/evil/exec_md.tar.gz readme.md

    # 3. bad_json.tar.gz
    mkdir -p /tmp/evil3
    echo '{"bad": true,}' > /tmp/evil3/metadata.json
    cd /tmp/evil3 && tar -czf /app/corpora/evil/bad_json.tar.gz metadata.json

    # 4. shell_injection.tar.gz
    mkdir -p /tmp/evil4
    echo 'Author: $(rm -rf /)' > /tmp/evil4/changelog.log
    cd /tmp/evil4 && tar -czf /app/corpora/evil/shell_injection.tar.gz changelog.log

    # Cleanup tmp
    rm -rf /tmp/clean* /tmp/evil*

    # Create user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
