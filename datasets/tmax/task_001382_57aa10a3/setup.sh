#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-venv espeak ffmpeg
    pip3 install pytest

    mkdir -p /home/user/project
    cat << 'EOF' > /home/user/project/requirements.txt
fastapi==0.68.0
pydantic==2.0.0
starlette==0.14.2
EOF

    mkdir -p /app/corpus/clean /app/corpus/evil

    # Generate audio instruction
    espeak -w /app/instruction.wav "The GoLite sanitizer must explicitly block any script containing the keywords FORK, SYS, or SOCKET. Additionally, reject any script where a SPAWN command is nested inside another SPAWN block, as this leads to resource exhaustion."

    # Create clean corpus
    cat << 'EOF' > /app/corpus/clean/clean1.gl
CHAN results
SPAWN func1
SEND results 42
RECV results
EOF

    cat << 'EOF' > /app/corpus/clean/clean2.gl
CHAN data
SPAWN worker
SEND data 1
RECV data
EOF

    cat << 'EOF' > /app/corpus/clean/clean3.gl
SPAWN main
CHAN a
EOF

    cat << 'EOF' > /app/corpus/clean/clean4.gl
CHAN b
SEND b 2
EOF

    cat << 'EOF' > /app/corpus/clean/clean5.gl
RECV c
EOF

    # Create evil corpus
    cat << 'EOF' > /app/corpus/evil/evil1.gl
CHAN boom
SPAWN func1
SPAWN func2
SYS REBOOT
EOF

    cat << 'EOF' > /app/corpus/evil/evil2.gl
SPAWN func1
   SPAWN func2
EOF

    cat << 'EOF' > /app/corpus/evil/evil3.gl
FORK process
EOF

    cat << 'EOF' > /app/corpus/evil/evil4.gl
SOCKET connect
EOF

    cat << 'EOF' > /app/corpus/evil/evil5.gl
SPAWN a
SPAWN b
  SPAWN c
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
    chmod -R 777 /app
