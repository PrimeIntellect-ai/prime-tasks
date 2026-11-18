#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc g++ ruby
    pip3 install pytest

    mkdir -p /app/sdk/include
    mkdir -p /app/corpora/clean
    mkdir -p /app/corpora/evil
    mkdir -p /home/user/legacy

    cat << 'EOF' > /app/sdk/include/packet.h
#ifndef PACKET_H
#define PACKET_H
int packet_get_meta();
int packet_validate(const char* data);
#endif
EOF

    cat << 'EOF' > /app/sdk/include/crypto.h
#ifndef CRYPTO_H
#define CRYPTO_H
int crypto_validate(const char* data);
#endif
EOF

    cat << 'EOF' > /tmp/libpacket.c
#include "packet.h"
#include "crypto.h"
int packet_get_meta() { return 42; }
int packet_validate(const char* data) {
    return crypto_validate(data) + 1;
}
EOF

    cat << 'EOF' > /tmp/libcrypto.c
#include "crypto.h"
#include "packet.h"
int crypto_validate(const char* data) {
    return packet_get_meta() + 1;
}
EOF

    gcc -shared -fPIC -I/app/sdk/include -o /app/sdk/libpacket.so /tmp/libpacket.c
    gcc -shared -fPIC -I/app/sdk/include -o /app/sdk/libcrypto.so /tmp/libcrypto.c

    cat << 'EOF' > /tmp/oracle.c
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>

int main(int argc, char** argv) {
    if (argc < 2) return 2;
    FILE* f = fopen(argv[1], "rb");
    if (!f) return 2;
    uint8_t buf[64];
    size_t n = fread(buf, 1, 64, f);
    fclose(f);
    if (n != 64) return 2;

    uint32_t magic = (buf[0] << 24) | (buf[1] << 16) | (buf[2] << 8) | buf[3];
    if (magic != 0xCAFEBABE) return 2;

    for (int i = 4; i < 64; i++) {
        buf[i] ^= 0x5A;
    }

    for (int i = 4; i <= 64 - 4; i++) {
        if (buf[i] == 0xDE && buf[i+1] == 0xAD && buf[i+2] == 0xBE && buf[i+3] == 0xEF) {
            return 1;
        }
    }

    return 0;
}
EOF

    gcc /tmp/oracle.c -o /app/oracle_stripped -s

    cat << 'EOF' > /home/user/legacy/parser.rb
#!/usr/bin/env ruby
if ARGV.length != 1
  exit 2
end
data = File.read(ARGV[0], mode: 'rb')
if data.bytesize != 64
  exit 2
end
magic = data[0..3].unpack1('N')
if magic != 0xCAFEBABE
  exit 2
end
payload = data[4..-1].bytes.map { |b| b ^ 0x5A }.pack('C*')
if payload.include?("\xDE\xAD\xBE\xEF".b)
  exit 1
end
exit 0
EOF
    chmod +x /home/user/legacy/parser.rb

    python3 -c '
import os
clean_data = b"\xca\xfe\xba\xbe" + bytes([0 ^ 0x5A] * 60)
with open("/app/corpora/clean/1.bin", "wb") as f:
    f.write(clean_data)

evil_data = b"\xca\xfe\xba\xbe" + bytes([0 ^ 0x5A] * 10) + bytes([0xDE^0x5A, 0xAD^0x5A, 0xBE^0x5A, 0xEF^0x5A]) + bytes([0 ^ 0x5A] * 46)
with open("/app/corpora/evil/1.bin", "wb") as f:
    f.write(evil_data)
'

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
