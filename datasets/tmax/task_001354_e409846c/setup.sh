#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        python3-dev \
        cmake \
        gcc \
        g++ \
        make \
        golang

    pip3 install pytest

    # Create directories
    mkdir -p /home/user/app/proxy
    mkdir -p /home/user/app/backend/ctrie
    mkdir -p /home/user/app/corpora/clean
    mkdir -p /home/user/app/corpora/evil

    # Create proxy/main.go
    cat << 'EOF' > /home/user/app/proxy/main.go
package main

import (
	"io"
	"log"
	"net/http"
)

func handleRequest(w http.ResponseWriter, r *http.Request) {
	req, err := http.NewRequest(r.Method, "http://127.0.0.1:8081", r.Body)
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	req.Header = r.Header

	client := &http.Client{}
	resp, err := client.Do(req)
	if err != nil {
		http.Error(w, err.Error(), http.StatusBadGateway)
		return
	}
	defer resp.Body.Close()

	for k, v := range resp.Header {
		w.Header()[k] = v
	}
	w.WriteHeader(resp.StatusCode)
	io.Copy(w, resp.Body)
}

func main() {
	http.HandleFunc("/", handleRequest)
	log.Println("Proxy listening on :8080")
	log.Fatal(http.ListenAndServe(":8080", nil))
}
EOF

    # Create backend/server.py
    cat << 'EOF' > /home/user/app/backend/server.py
import BaseHTTPServer
import json
import ctrie

class RequestHandler(BaseHTTPServer.BaseHTTPRequestHandler):
    def do_POST(self):
        content_length = int(self.headers.getheader('content-length', 0))
        post_data = self.rfile.read(content_length)
        print "Received request:", post_data

        self.send_response(200)
        self.send_header('Content-type', 'application/json')
        self.end_headers()
        self.wfile.write('{"status": "ok"}')

if __name__ == '__main__':
    server_address = ('127.0.0.1', 8081)
    httpd = BaseHTTPServer.HTTPServer(server_address, RequestHandler)
    print "Backend listening on port 8081"
    httpd.serve_forever()
EOF

    # Create backend/ctrie/CMakeLists.txt
    cat << 'EOF' > /home/user/app/backend/ctrie/CMakeLists.txt
cmake_minimum_required(VERSION 3.10)
project(ctrie)

set(CMAKE_C_STANDARD 99)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

find_package(PythonLibs REQUIRED)
include_directories(${PYTHON_INCLUDE_DIRS})

add_library(ctrie SHARED ctrie.c)
target_link_libraries(ctrie ${PYTHON_LIBRARIES})
set_target_properties(ctrie PROPERTIES PREFIX "")
EOF

    # Create backend/ctrie/ctrie.c
    cat << 'EOF' > /home/user/app/backend/ctrie/ctrie.c
#include <Python.h>

static PyObject* ctrie_init(PyObject* self, PyObject* args) {
    Py_RETURN_NONE;
}

static PyMethodDef CtrieMethods[] = {
    {"init", ctrie_init, METH_VARARGS, "Init"},
    {NULL, NULL, 0, NULL}
};

PyMODINIT_FUNC initctrie(void) {
    (void) Py_InitModule("ctrie", CtrieMethods);
}
EOF

    # Create corpora files
    for i in $(seq 1 15); do
        echo "{\"query\": \"benign query $i\", \"is_admin\": false}" > /home/user/app/corpora/clean/c${i}.json
        echo "{\"query\": \"SELECT * 'OR 1=1'\", \"is_admin\": false}" > /home/user/app/corpora/evil/e_sql${i}.json
        echo "{\"query\": \"hello\", \"is_admin\": true}" > /home/user/app/corpora/evil/e_admin${i}.json
    done

    # Create start.sh
    cat << 'EOF' > /home/user/app/start.sh
#!/bin/bash

cd /home/user/app/backend/ctrie
mkdir -p build
cd build
cmake ..
make
cp *.so ../../

cd /home/user/app/proxy
go build -o proxy main.go

cd /home/user/app
./proxy/proxy &
PROXY_PID=$!

cd /home/user/app/backend
python3 server.py &
BACKEND_PID=$!

wait
EOF
    chmod +x /home/user/app/start.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
