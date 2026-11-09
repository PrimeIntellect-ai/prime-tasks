#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc make protobuf-c-compiler libprotobuf-c-dev tesseract-ocr imagemagick fonts-liberation
pip3 install pytest protobuf grpcio-tools

mkdir -p /app/schema /app/src /app/docs /app/corpus/clean /app/corpus/evil /app/build

# 1. Create the proto file
cat << 'EOF' > /app/schema/trace.proto
syntax = "proto3";
message Event {
  string type = 1;
}
message Trace {
  repeated Event events = 1;
}
EOF

# 2. Create the broken Makefile
cat << 'EOF' > /app/Makefile
CC = gcc
CFLAGS = -Wall -I. -I./schema
LDFLAGS = -lprotobuf  # BROKEN: should be -lprotobuf-c

all: /app/build/validator

# BROKEN: uses protoc instead of protoc-c, wrong output flag
/app/schema/trace.pb-c.c /app/schema/trace.pb-c.h: /app/schema/trace.proto
	protoc --cpp_out=/app/schema /app/schema/trace.proto

/app/build/validator: /app/src/validator.c /app/schema/trace.pb-c.c
	$(CC) $(CFLAGS) -o $@ $^ $(LDFLAGS)

clean:
	rm -rf /app/build/* /app/schema/*.pb-c.*
EOF

# 3. Create the C skeleton
cat << 'EOF' > /app/src/validator.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "schema/trace.pb-c.h"

// TODO: Implement state machine validation
// Return 1 if valid, 0 if invalid
int validate_trace(Trace *trace) {
    // Read /app/docs/statemachine.png to understand the rules.
    return 0; 
}

int main(int argc, char **argv) {
    if (argc != 2) return 1;

    FILE *f = fopen(argv[1], "rb");
    if (!f) return 1;

    fseek(f, 0, SEEK_END);
    long len = ftell(f);
    fseek(f, 0, SEEK_SET);

    uint8_t *buf = malloc(len);
    fread(buf, 1, len, f);
    fclose(f);

    Trace *trace = trace__unpack(NULL, len, buf);
    free(buf);

    if (!trace) return 1;

    int is_valid = validate_trace(trace);
    trace__free_unpacked(trace, NULL);

    return is_valid ? 0 : 1;
}
EOF

# 4. Generate the image fixture
convert -background white -fill black -font Courier -pointsize 24 \
  label:"VALID STATE TRANSITIONS:\nINIT -> AUTH\nAUTH -> QUERY\nQUERY -> QUERY\nQUERY -> LOGOUT\nLOGOUT -> END\n\nAny other transition is INVALID.\nMust start at INIT and finish at END." \
  /app/docs/statemachine.png

# 5. Generate python script to create binary corpora
cat << 'EOF' > /tmp/gen_corpus.py
import sys
import subprocess
subprocess.run([sys.executable, "-m", "grpc_tools.protoc", "-I/app/schema", "--python_out=/tmp", "/app/schema/trace.proto"])
sys.path.append("/tmp")
import trace_pb2

def write_trace(path, events):
    t = trace_pb2.Trace()
    for e in events:
        ev = t.events.add()
        ev.type = e
    with open(path, "wb") as f:
        f.write(t.SerializeToString())

# Clean corpus
write_trace("/app/corpus/clean/trace1.bin", ["INIT", "AUTH", "QUERY", "LOGOUT", "END"])
write_trace("/app/corpus/clean/trace2.bin", ["INIT", "AUTH", "QUERY", "QUERY", "QUERY", "LOGOUT", "END"])
write_trace("/app/corpus/clean/trace3.bin", ["INIT", "AUTH", "QUERY", "QUERY", "LOGOUT", "END"])

# Evil corpus
write_trace("/app/corpus/evil/trace1.bin", ["INIT", "AUTH", "LOGOUT", "END"]) # Missing QUERY
write_trace("/app/corpus/evil/trace2.bin", ["AUTH", "QUERY", "LOGOUT", "END"]) # Missing INIT
write_trace("/app/corpus/evil/trace3.bin", ["INIT", "AUTH", "QUERY", "LOGOUT"]) # Missing END
write_trace("/app/corpus/evil/trace4.bin", ["INIT", "AUTH", "QUERY", "QUERY", "AUTH", "LOGOUT", "END"]) # Invalid transition
write_trace("/app/corpus/evil/trace5.bin", ["INIT", "AUTH", "QUERY", "LOGOUT", "END", "INIT"]) # Trailing junk
write_trace("/app/corpus/evil/trace6.bin", []) # Empty
EOF
python3 /tmp/gen_corpus.py
rm /tmp/gen_corpus.py

chmod -R 755 /app

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
