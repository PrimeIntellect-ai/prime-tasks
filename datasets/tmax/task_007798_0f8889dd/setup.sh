#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip strace
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/process_data.sh
#!/bin/bash
INPUT_FILE=$1
if [ ! -f "$INPUT_FILE" ]; then
    echo "Usage: $0 <input_file>"
    exit 1
fi

while IFS= read -r line; do
    if [ "$line" == "HALT" ]; then
        # Buggy infinite loop
        while [ ! -e "/tmp/worker.sock" ]; do
            sleep 0.1
        done
    fi
    echo "Processed $line" > /dev/null
done < "$INPUT_FILE"
EOF

    chmod +x /home/user/process_data.sh

    cat << 'EOF' > /home/user/words.txt
APPLE
BANANA
CHERRY
DOG
EAGLE
FISH
GRAPE
HALT
IGLOO
JUMP
KITE
LEMON
EOF

    chmod -R 777 /home/user
