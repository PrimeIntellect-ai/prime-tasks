#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc valgrind
    pip3 install --default-timeout=100 pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/ws_interp.c
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>

// Causes compilation error: unknown type name 'InterpreterState'
typedef struct {
    uint8_t opcode;
    int32_t payload;
    InterpreterState* state; 
} WebSocketFrame;

typedef struct {
    int accumulator;
    WebSocketFrame* last_frame;
} InterpreterState;

void process_frame(InterpreterState* state, WebSocketFrame* frame) {
    if (frame->opcode == 0x01) {
        state->accumulator += frame->payload;
    }
    // memory leak: we override last_frame without freeing the old one
    if (state->last_frame) {
        // missing free(state->last_frame);
    }
    state->last_frame = frame;
}

int main() {
    InterpreterState state = {0, NULL};
    uint8_t opcode;
    int32_t payload;

    while (fread(&opcode, 1, 1, stdin) == 1) {
        if (fread(&payload, 4, 1, stdin) != 1) break;

        WebSocketFrame* frame = malloc(sizeof(WebSocketFrame));
        frame->opcode = opcode;
        frame->payload = payload;

        process_frame(&state, frame);
    }

    printf("FINAL_ACCUMULATOR: %d\n", state.accumulator);

    // missing free(state.last_frame);
    return 0;
}
EOF

    python3 -c '
import sys
with open("/home/user/payload.bin", "wb") as f:
    f.write(bytes([
        0x01, 0x0A, 0x00, 0x00, 0x00,
        0x01, 0x14, 0x00, 0x00, 0x00,
        0x01, 0x0C, 0x00, 0x00, 0x00
    ]))
'

    chmod -R 777 /home/user
