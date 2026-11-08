#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go build-essential
    pip3 install pytest

    mkdir -p /home/user/audio-svc/parser
    mkdir -p /app

    cat << 'EOF' > /home/user/audio-svc/go.mod
module audio-svc

go 1.18
EOF

    cat << 'EOF' > /home/user/audio-svc/parser/libaudio.h
#ifndef LIBAUDIO_H
#define LIBAUDIO_H

typedef struct {
    int req_id;
    char* raw_text;
    int timestamp;
} AudioMetadata;

AudioMetadata* extract_metadata(const char* filepath);

#endif
EOF

    cat << 'EOF' > /home/user/audio-svc/parser/libaudio.c
#include "libaudio.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

AudioMetadata* extract_metadata(const char* filepath) {
    FILE* f = fopen(filepath, "rb");
    if (!f) return NULL;

    fseek(f, 0, SEEK_END);
    long size = ftell(f);
    fseek(f, 0, SEEK_SET);

    char* buffer = malloc(size);
    fread(buffer, 1, size, f);
    fclose(f);

    AudioMetadata* meta = malloc(sizeof(AudioMetadata));
    meta->req_id = 0;
    meta->raw_text = NULL;
    meta->timestamp = 123456;

    for (long i = 0; i < size - 8; i++) {
        if (buffer[i] == 'T' && buffer[i+1] == 'R' && buffer[i+2] == 'N' && buffer[i+3] == 'S') {
            int chunk_size = *(int*)(&buffer[i+4]);
            meta->req_id = *(int*)(&buffer[i+8]);
            int text_len = chunk_size - 4;
            meta->raw_text = malloc(text_len);
            // Intentional off-by-one error:
            for(int j=0; j<=text_len; j++) {
                meta->raw_text[j] = buffer[i+12+j];
            }
            break;
        }
    }
    // Intentional missing free(buffer);
    return meta;
}
EOF

    cat << 'EOF' > /home/user/audio-svc/parser/parser.go
package parser

/*
#cgo CFLAGS: -I.
#include "libaudio.h"
#include <stdlib.h>
*/
import "C"
import "unsafe"

type Metadata struct {
	ReqID    int
	RawText  string
	Timestamp int
}

func ExtractMetadata(filepath string) *Metadata {
	cpath := C.CString(filepath)
	defer C.free(unsafe.Pointer(cpath))

	cmeta := C.extract_metadata(cpath)
	if cmeta == nil {
		return nil
	}

	meta := &Metadata{
		ReqID:    int(cmeta.req_id),
		RawText:  C.GoString(cmeta.raw_text),
		Timestamp: int(cmeta.timestamp),
	}

	return meta
}
EOF

    cat << 'EOF' > /home/user/audio-svc/main.go
package main

import (
	"fmt"
	"net/http"
	"audio-svc/parser"
)

func main() {
	http.HandleFunc("/api/v1/extract", func(w http.ResponseWriter, r *http.Request) {
		// Semver logic missing
		meta := parser.ExtractMetadata("/app/transmission.wav")
		if meta != nil {
			fmt.Fprintf(w, "Extracted: %s", meta.RawText)
		}
	})
	http.ListenAndServe("127.0.0.1:8080", nil)
}
EOF

    python3 -c '
import wave
import struct

with wave.open("/app/transmission.wav", "wb") as w:
    w.setnchannels(1)
    w.setsampwidth(2)
    w.setframerate(44100)
    w.writeframes(b"\x00\x00" * 10)

with open("/app/transmission.wav", "ab") as f:
    payload = struct.pack("<I", 104) + b"Eagle has landed"
    chunk_header = b"TRNS" + struct.pack("<I", len(payload))
    f.write(chunk_header + payload)
'

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
    chmod -R 777 /app
