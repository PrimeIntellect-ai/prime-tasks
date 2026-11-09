#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gzip gawk coreutils sed
    pip3 install pytest

    # Create log-archiver directory and unarchive.sh
    mkdir -p /app/log-archiver-1.0/bin
    cat << 'EOF' > /app/log-archiver-1.0/bin/unarchive.sh
#!/bin/bash
# log-archiver unarchive script
# Version 1.0
#
#
#
#
#
#
#
#
#

$GZ_BIN -d -c "$1"
EOF
    chmod +x /app/log-archiver-1.0/bin/unarchive.sh

    # Create oracle script
    mkdir -p /opt/oracle
    cat << 'EOF' > /opt/oracle/process_archive_oracle.sh
#!/bin/bash
# Oracle implementation for fuzzing
HEADER_HEX=$(head -c 8 "$1")
HEADER_LEN=$((16#$HEADER_HEX))
SKIP_BYTES=$((9 + HEADER_LEN))
tail -c +$((SKIP_BYTES + 1)) "$1" > /tmp/payload.gz
gzip -d -c /tmp/payload.gz > /tmp/extracted.log
awk -v sev="[$2]" '
    /^\[[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}\]/ {
        if (match_found && buffer != "") {
            print buffer "\n"
        }
        if (index($0, sev) > 0) {
            match_found = 1
            buffer = $0
        } else {
            match_found = 0
            buffer = ""
        }
        next
    }
    {
        if (match_found) {
            buffer = buffer "\n" $0
        }
    }
    END {
        if (match_found && buffer != "") {
            print buffer "\n"
        }
    }
' /tmp/extracted.log | sed '/^$/N;/^\n$/D' | sed '$d'
EOF
    chmod +x /opt/oracle/process_archive_oracle.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
