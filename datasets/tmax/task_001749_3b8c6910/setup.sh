#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc gdb bc
    pip3 install pytest

    mkdir -p /app/bin
    mkdir -p /app/hidden
    mkdir -p /home/user/cores

    # Create freq_extract C source and compile
    cat << 'EOF' > /app/freq_extract.c
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

int main(int argc, char **argv) {
    int safe_mode = 0;
    for(int i=1; i<argc; i++) {
        if(strcmp(argv[i], "--safe-mode") == 0) {
            safe_mode = 1;
        }
    }
    if(!safe_mode) {
        int *p = NULL;
        *p = 42; // Intentionally crash
    }
    printf("freq_footprint_12345\n");
    return 0;
}
EOF
    gcc -g -o /app/bin/freq_extract /app/freq_extract.c
    rm /app/freq_extract.c

    # Create sample_audio.wav using Python
    python3 -c "
import wave, struct
with wave.open('/app/sample_audio.wav', 'w') as w:
    w.setnchannels(1)
    w.setsampwidth(2)
    w.setframerate(44100)
    w.writeframesraw(struct.pack('<h', 0)*44100)
"

    # Create buggy process_audio.sh
    cat << 'EOF' > /home/user/process_audio.sh
#!/bin/bash
vol="10.5"
target="10.0"
# Buggy float comparison using expr
while [ $(expr $vol \> $target 2>/dev/null) -eq 1 ]; do
    echo "Normalizing..." >> /home/user/pipeline.log
    # Stuck in infinite loop due to bash float truncation
done
/app/bin/freq_extract "$1"
EOF
    chmod +x /home/user/process_audio.sh

    # Create oracle_processor.sh
    cat << 'EOF' > /app/hidden/oracle_processor.sh
#!/bin/bash
/app/bin/freq_extract --safe-mode "$1"
EOF
    chmod +x /app/hidden/oracle_processor.sh

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user /app
    chmod -R 777 /home/user /app
