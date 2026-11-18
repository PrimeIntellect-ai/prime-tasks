#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip fuse2fs systemd wget curl grep gawk sed
    pip3 install pytest

    # Create vendored package directory and file
    mkdir -p /app/bash-ini-parser

    # We will download the real bash-ini-parser if possible, but fallback to a mock
    # since we need it to parse INI files for the verifier.
    wget -qO /app/bash-ini-parser/bash-ini-parser.sh https://raw.githubusercontent.com/albfan/bash-ini-parser/master/bash-ini-parser || true

    # If download failed or doesn't contain the target line, we'll ensure the file exists
    # and has the required syntax error for the test.
    if [ ! -s /app/bash-ini-parser/bash-ini-parser.sh ]; then
        cat << 'EOF' > /app/bash-ini-parser/bash-ini-parser.sh
#!/bin/bash
# Mock bash-ini-parser
cfg.parser() {
    local IN_SECTION=true
    if [ "$IN_SECTION" = true ; then
        :
    fi
    while IFS='= ' read -r k v; do
        if [[ "$k" =~ ^\[.*\]$ ]]; then
            continue
        elif [ -n "$k" ] && [ -n "$v" ]; then
            eval "${k}=${v}"
        fi
    done < "$1"
}
EOF
    else
        # If downloaded, inject the syntax error somewhere to satisfy the test
        echo 'if [ "$IN_SECTION" = true ; then' >> /app/bash-ini-parser/bash-ini-parser.sh
    fi
    chmod +x /app/bash-ini-parser/bash-ini-parser.sh

    # Create Oracle script
    mkdir -p /verifier
    cat << 'EOF' > /verifier/oracle_analyze_restore.sh
#!/bin/bash
input=$(cat)
job_id=$(echo "$input" | grep -oP "Starting restore job \K\d+")
total_restored=$(echo "$input" | grep -oP "Restored \K\d+(?= files)")
error_count=$(echo "$input" | grep -oP "Job finished with \K\d+(?= errors\.)")
if [ -z "$error_count" ]; then error_count=0; fi

failed_files=$(echo "$input" | grep -oP "Failed to extract: \K[^\s]+" | paste -sd "," -)
if [ -z "$failed_files" ]; then failed_files="NONE"; fi

echo "JOB: $job_id"
echo "TOTAL_RESTORED: $total_restored"
echo "ERROR_COUNT: $error_count"
echo "FAILED_FILES: $failed_files"
EOF
    chmod +x /verifier/oracle_analyze_restore.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
