#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang gcc ffmpeg
    pip3 install pytest

    mkdir -p /home/user/vid-parser/lib
    mkdir -p /app

    cat << 'EOF' > /home/user/vid-parser/lib/vidproc.h
#ifndef VIDPROC_H
#define VIDPROC_H
#include <stdint.h>

#pragma pack(push, 1)
typedef struct {
    uint32_t frame_id;
    uint8_t semver_len;
    char semver_str[32];
    uint16_t checksum;
} MetadataPayload;
#pragma pack(pop)

MetadataPayload* process_frame(const unsigned char* frame_data, int width, int height);
void free_payload(MetadataPayload* payload);

#endif
EOF

    cat << 'EOF' > /tmp/vidproc.c
#include "vidproc.h"
#include <stdlib.h>
MetadataPayload* process_frame(const unsigned char* frame_data, int width, int height) {
    return NULL;
}
void free_payload(MetadataPayload* payload) {}
EOF

    gcc -shared -fPIC -o /home/user/vid-parser/lib/libvidproc.so /tmp/vidproc.c -I/home/user/vid-parser/lib

    cat << 'EOF' > /home/user/vid-parser/processor.go
package main

// #cgo CFLAGS: -I${SRCDIR}/lib
// #include "vidproc.h"
import "C"

type MetadataPayload struct {
    FrameID   uint32
    SemverLen uint8
    SemverStr [32]byte
    Checksum  uint16
}

func main() {
}
EOF

    touch /app/test_sequence.mp4

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
