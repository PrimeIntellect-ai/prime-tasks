#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl gcc golang espeak
    pip3 install pytest

    mkdir -p /app
    espeak -w /app/voicemail.wav "Hey, it's Dave. We had to reset the server config. Make sure the new deployment uses the secret multiplier of seven. Thanks."

    mkdir -p /home/user/workspace/lib
    cat << 'EOF' > /home/user/workspace/lib/process.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

char* encode_string(const char* input, int multiplier) {
    char* out = malloc(100);
    strcpy(out, input);
    for(int i=0; i<strlen(out); i++) {
        out[i] = out[i] + multiplier;
    }
    return out;
}
EOF

    mkdir -p /home/user/workspace/api
    cat << 'EOF' > /home/user/workspace/api/server.go
package main

/*
#cgo LDFLAGS: -L../lib -lprocess
#include <stdlib.h>
char* encode_string(const char* input, int multiplier);
*/
import "C"
import (
    "unsafe"
    "net/http"
    "strconv"
    "encoding/json"
)

var globalInput *C.char

func computeHandler(w http.ResponseWriter, r *http.Request) {
    input := r.URL.Query().Get("input")
    multStr := r.URL.Query().Get("multiplier")
    mult, _ := strconv.Atoi(multStr)

    globalInput = C.CString(input)
    defer C.free(unsafe.Pointer(globalInput))

    resC := C.encode_string(globalInput, C.int(mult))
    defer C.free(unsafe.Pointer(resC))

    res := C.GoString(resC)
    json.NewEncoder(w).Encode(map[string]string{"result": res})
}

func main() {
    http.HandleFunc("/compute", computeHandler)
    http.ListenAndServe(":8080", nil)
}
EOF

    cat << 'EOF' > /app/oracle_query
#!/usr/bin/env python3
import sys

if len(sys.argv) < 2:
    sys.exit(0)

input_str = sys.argv[1][:10]
res = "".join(chr(ord(c) + 7) for c in input_str)
print(res)
EOF
    chmod +x /app/oracle_query

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
