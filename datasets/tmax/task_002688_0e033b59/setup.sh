#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ golang-go nginx curl
    pip3 install pytest

    mkdir -p /home/user/telemetry-system/corpus/clean
    mkdir -p /home/user/telemetry-system/corpus/evil

    cd /home/user/telemetry-system

    cat << 'EOF' > worker.cpp
#include <iostream>
#include <string>
#include <sys/socket.h>
#include <netinet/in.h>
#include <unistd.h>

int main() {
    int server_fd = socket(AF_INET, SOCK_STREAM, 0);
    struct sockaddr_in address;
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = INADDR_ANY;
    address.sin_port = htons(9001);
    bind(server_fd, (struct sockaddr *)&address, sizeof(address));
    listen(server_fd, 3);
    while(true) {
        int new_socket = accept(server_fd, nullptr, nullptr);
        const char* resp = "HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nOK";
        write(new_socket, resp, 38);
        close(new_socket);
    }
    return 0;
}
EOF

    cat << 'EOF' > main.go
package main
import (
    "encoding/json"
    "net/http"
)
type Payload struct {
    SeriesA []int `json:"series_a"`
    SeriesB []int `json:"series_b"`
}
func processHandler(w http.ResponseWriter, r *http.Request) {
    var p Payload
    if err := json.NewDecoder(r.Body).Decode(&p); err != nil {
        http.Error(w, "Bad Request", http.StatusBadRequest)
        return
    }
    if !ValidateTelemetry(p.SeriesA, p.SeriesB) {
        http.Error(w, "Anomaly Detected", http.StatusBadRequest)
        return
    }
    // Simulate passing to C++ worker
    http.Get("http://127.0.0.1:9001")
    w.WriteHeader(http.StatusOK)
}
func main() {
    http.HandleFunc("/api/process", processHandler)
    http.ListenAndServe(":9000", nil)
}
EOF

    cat << 'EOF' > validator.go
package main

// ValidateTelemetry returns true if the telemetry is valid, false otherwise.
func ValidateTelemetry(a, b []int) bool {
    // TODO: Implement validation logic
    return true
}
EOF

    echo '{"series_a": [1, 5, 12], "series_b": [3, 8, 15]}' > corpus/clean/c1.json
    echo '{"series_a": [10, 20, 30], "series_b": [15, 25, 35]}' > corpus/clean/c2.json

    echo '{"series_a": [1, 5, 4], "series_b": [3, 8, 15]}' > corpus/evil/e1.json
    echo '{"series_a": [1, 5, 12], "series_b": [3, 8, 7]}' > corpus/evil/e2.json
    echo '{"series_a": [1, 5, 20], "series_b": [3, 8, 10]}' > corpus/evil/e3.json
    echo '{"series_a": [1, 1, 5], "series_b": [3, 8, 10]}' > corpus/evil/e4.json

    cat << 'EOF' > start_services.sh
#!/bin/bash
# Broken startup script
echo "Starting services..."
EOF
    chmod +x start_services.sh

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
