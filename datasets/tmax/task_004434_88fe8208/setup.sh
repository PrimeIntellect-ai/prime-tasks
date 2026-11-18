#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go curl
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/app/backend
    mkdir -p /home/user/app/proxy

    cat << 'EOF' > /home/user/app/backend/main.go
package main

import (
	"encoding/json"
	"io"
	"net/http"
)

func main() {
	http.HandleFunc("/status", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		w.Write([]byte(`{"status": "ok"}`))
	})
	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		if r.Method == http.MethodPost {
			body, _ := io.ReadAll(r.Body)
			var data interface{}
			if err := json.Unmarshal(body, &data); err == nil {
				resp := map[string]interface{}{
					"status": "ok",
					"echo":   data,
				}
				w.Header().Set("Content-Type", "application/json")
				json.NewEncoder(w).Encode(resp)
				return
			}
		}
		w.WriteHeader(http.StatusOK)
	})
	http.ListenAndServe("127.0.0.1:8081", nil)
}
EOF

    cat << 'EOF' > /home/user/app/proxy/server.py
import SocketServer
import BaseHTTPServer
import urllib2

class ProxyHandler(BaseHTTPServer.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.end_headers()
        self.wfile.write("Python 2 Proxy")

if __name__ == "__main__":
    pass
EOF

    cat << 'EOF' > /home/user/app/start_services.sh
#!/bin/bash
cd /home/user/app/backend
go build -o backend main.go
./backend > backend.log 2>&1 &
sleep 2
EOF
    chmod +x /home/user/app/start_services.sh

    # Run the start script so the backend is compiled
    # The background process will die at the end of %post, but the binary will be built.
    # We also add it to a .bashrc or similar if needed, but the test runner likely executes it.
    /home/user/app/start_services.sh

    chmod -R 777 /home/user
