#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang gcc build-essential
    pip3 install pytest

    mkdir -p /home/user/workspace/auth
    cd /home/user/workspace/auth

    go mod init auth

    cat << 'EOF' > main.go
package main

/*
extern int check_sig(char* msg);
int validate_token(char* token) {
    return check_sig(token);
}
*/
import "C"
import (
    "net/http"
)

func Validate(token string) bool {
    return C.validate_token(C.CString(token)) == 1
}

func AuthHandler(w http.ResponseWriter, r *http.Request) {
    token := r.URL.Query().Get("token")
    if Validate(token) {
        w.WriteHeader(http.StatusOK)
        w.Write([]byte("OK"))
    } else {
        w.WriteHeader(http.StatusUnauthorized)
    }
}

func main() {
    http.HandleFunc("/auth", AuthHandler)
    http.ListenAndServe(":8080", nil)
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
