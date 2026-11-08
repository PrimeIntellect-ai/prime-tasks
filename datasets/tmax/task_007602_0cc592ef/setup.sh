#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc binutils
pip3 install pytest

useradd -m -s /bin/bash user || true

cat << 'EOF' > /tmp/profiler_dump.c
#include <stdio.h>
#include <stdint.h>
#include <string.h>

#pragma pack(push, 1)
struct ProfileEvent {
    uint32_t timestamp;
    uint16_t event_type;
    char function_name[26];
};
#pragma pack(pop)

int main() {
    FILE *f = fopen("/home/user/events.bin", "wb");
    if(!f) return 1;
    struct ProfileEvent ev1 = { 1625091234, 1, "main" };
    struct ProfileEvent ev2 = { 1625091240, 2, "compute_hash" };
    struct ProfileEvent ev3 = { 1625091245, 2, "validate_data" };
    fwrite(&ev1, sizeof(struct ProfileEvent), 1, f);
    fwrite(&ev2, sizeof(struct ProfileEvent), 1, f);
    fwrite(&ev3, sizeof(struct ProfileEvent), 1, f);
    fclose(f);
    return 0;
}
EOF

gcc -g /tmp/profiler_dump.c -o /home/user/profiler_dump
chmod +x /home/user/profiler_dump
rm /tmp/profiler_dump.c

cat << 'EOF' > /home/user/parse_events.py
import struct
import json

def parse():
    events = []
    with open('/home/user/events.bin', 'rb') as f:
        # BUG: The chunk size and struct format are incorrect!
        while chunk := f.read(30):
            if len(chunk) < 30: break
            ts, ev_type, name = struct.unpack('<IH24s', chunk)
            events.append({
                'timestamp': ts,
                'event_type': ev_type,
                'function_name': name.decode('ascii').strip('\x00')
            })

    with open('/home/user/events.json', 'w') as f:
        json.dump(events, f, indent=2)

if __name__ == '__main__':
    parse()
EOF

chmod -R 777 /home/user
