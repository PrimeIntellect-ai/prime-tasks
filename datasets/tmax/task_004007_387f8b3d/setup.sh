#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip e2tools extundelete sleuthkit bc gawk e2fsprogs
    pip3 install pytest

    mkdir -p /app/corpus/evil
    mkdir -p /app/corpus/clean

    # Mock whisper to avoid massive ML dependency downloads which cause timeouts
    cat << 'EOF' > /usr/local/bin/whisper
#!/bin/bash
echo "Use seed four two nine four nine six seven two nine five and set the boundary constraint to negative one."
EOF
    chmod +x /usr/local/bin/whisper

    # Create dummy audio file
    touch /app/intercepted_signal.wav

    # Create ext4 image and simulate deleted file using e2tools
    dd if=/dev/zero of=/app/workspace.img bs=1M count=10
    mkfs.ext4 -F /app/workspace.img

    cat << 'EOF' > /tmp/fuzzer.sh
#!/bin/bash
SEED=$1
BOUNDARY=$2
echo "Fuzzing with $SEED and $BOUNDARY"
EOF
    e2cp /tmp/fuzzer.sh /app/workspace.img:/fuzzer.sh
    e2rm /app/workspace.img:/fuzzer.sh
    rm /tmp/fuzzer.sh

    # Create extraction tool
    cat << 'EOF' > /app/extract.sh
#!/bin/bash
val1=$(cat $1 | awk '{print $1}')
val2=$(cat $1 | awk '{print $2}')
echo $(($val1 * $val2))
EOF
    chmod +x /app/extract.sh

    # Populate corpus
    echo "10000000000 10000000000" > /app/corpus/evil/evil_1.txt
    echo "9223372036854775807 2" > /app/corpus/evil/evil_2.txt

    echo "10 10" > /app/corpus/clean/clean_1.txt
    echo "5000 5000" > /app/corpus/clean/clean_2.txt

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
