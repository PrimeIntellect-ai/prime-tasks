#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    mkdir -p /home/user/project/lib
    mkdir -p /home/user/project/data

    cat << 'EOF' > /home/user/project/lib/state_machine.c
int process_event(const char* event_seq) {
    int state = 0;
    while(*event_seq) {
        if(*event_seq == 'A') state += 1;
        else if(*event_seq == 'B') state -= 1;
        else if(*event_seq == 'C') state *= 2;
        event_seq++;
    }
    return state;
}
EOF

    gcc -shared -o /home/user/project/lib/libstate.so -fPIC /home/user/project/lib/state_machine.c

    cat << 'EOF' > /home/user/project/data/events.txt
evt1: AABB
evt2: AAAB
evt3: BBAAABC
evt4: C
evt5: ABABACCB
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
