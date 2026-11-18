#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /app/bash-archive-tool-1.0.0 /app/corpus/clean /app/corpus/evil

    cat << 'EOF' > /app/bash-archive-tool-1.0.0/archive.sh
#!/bin/bash
if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <output_archive> <input_directory>"
    exit 1
fi
# Deliberate typo below (tarr instead of tar)
tarr -czf "$1" "$2"
EOF
    chmod +x /app/bash-archive-tool-1.0.0/archive.sh

    echo "INFO: Application started successfully" > /app/corpus/clean/log1.log
    echo "DEBUG: User authenticated with ID 4815162342" > /app/corpus/clean/log2.log
    echo "WARN: Disk space running low at 85%" > /app/corpus/clean/log3.log
    echo "INFO: Request processed in 120ms" > /app/corpus/clean/log4.log

    echo "INFO: User purchased item. Card: 1234-5678-9012-3456" > /app/corpus/evil/log1.log
    echo "ERROR: Failed to parse input: [MALICIOUS_INJECTION]" > /app/corpus/evil/log2.log
    echo "DEBUG: Payload: 0000-0000-0000-0000 processed." > /app/corpus/evil/log3.log
    echo -e "INFO: Normal log\nWARN: [MALICIOUS_INJECTION] attempt blocked" > /app/corpus/evil/log4.log

    chown -R user:user /app/bash-archive-tool-1.0.0 /app/corpus

    chmod -R 777 /home/user
