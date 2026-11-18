#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip socat gcc
    pip3 install pytest

    mkdir -p /app/sample_traffic
    mkdir -p /app/corpora/evil
    mkdir -p /app/corpora/clean

    cat << 'EOF' > /app/receiver.sh
#!/bin/bash
socat TCP-LISTEN:8000,fork,reuseaddr TCP:127.0.0.1:8001
EOF

    cat << 'EOF' > /app/processor.sh
#!/bin/bash
socat TCP-LISTEN:8001,fork,reuseaddr EXEC:/app/process_single.sh
EOF

    cat << 'EOF' > /app/start_services.sh
#!/bin/bash
/app/processor.sh &
/app/receiver.sh &
wait
EOF

    cat << 'EOF' > /app/process_single.sh
#!/bin/bash
read -r payload

if [[ ! "$payload" =~ ^TELEMETRY_(.*)_(.*)$ ]]; then
    echo "INVALID FORMAT"
    exit 1
fi

ID="${BASH_REMATCH[1]}"
VALUE="${BASH_REMATCH[2]}"

# Generate C code
C_FILE=$(mktemp /tmp/prog_XXXXXX.c)
BIN_FILE=$(mktemp /tmp/prog_XXXXXX)

cat << C_CODE > "$C_FILE"
#include <stdio.h>
int main() {
    int ${ID}_var = $VALUE;
    int val = ${ID}_var;
    while(val != 1) {
        if (val % 100 == 0) {
            // Bug: skip division, infinite loop
        } else if (val % 2 == 0) {
            val = val / 2;
        } else {
            val = 3 * val + 1;
        }
    }
    printf("Done\n");
    return 0;
}
C_CODE

gcc "$C_FILE" -o "$BIN_FILE" 2>/dev/null
if [ $? -ne 0 ]; then
    echo "COMPILER ERROR"
    rm -f "$C_FILE" "$BIN_FILE"
    exit 1
fi

# Run with a 2-second timeout
timeout 2 "$BIN_FILE"
if [ $? -eq 124 ]; then
    echo "CONVERGENCE FAILURE"
    rm -f "$C_FILE" "$BIN_FILE"
    exit 1
fi

echo "SUCCESS"
rm -f "$C_FILE" "$BIN_FILE"
exit 0
EOF

    chmod +x /app/receiver.sh /app/processor.sh /app/start_services.sh /app/process_single.sh

    # Generate corpora
    for i in $(seq 1 50); do
        echo "TELEMETRY_A$(printf "%03d" $i)_$((i*2 + 1))" > /app/corpora/clean/clean_$i.txt
    done

    for i in $(seq 1 25); do
        echo "TELEMETRY_a$(printf "%03d" $i)_$((i*2 + 1))" > /app/corpora/evil/evil_compiler_$i.txt
    done

    for i in $(seq 1 25); do
        echo "TELEMETRY_B$(printf "%03d" $i)_$((i*100))" > /app/corpora/evil/evil_converge_$i.txt
    done

    # Generate sample traffic
    cp /app/corpora/clean/clean_1.txt /app/sample_traffic/sample_1.txt
    cp /app/corpora/clean/clean_2.txt /app/sample_traffic/sample_2.txt
    cp /app/corpora/evil/evil_compiler_1.txt /app/sample_traffic/sample_3.txt
    cp /app/corpora/evil/evil_converge_1.txt /app/sample_traffic/sample_4.txt

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
