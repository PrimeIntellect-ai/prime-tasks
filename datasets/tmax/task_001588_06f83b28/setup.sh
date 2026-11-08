#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc golang-go
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/auth_svc.c
#include <stdio.h>
int main() {
    printf("Auth Service\n");
    return 0;
}
EOF

    cat << 'EOF' > /home/user/data_svc.go
package main
import "fmt"
func main() {
    fmt.Println("Data Service")
}
EOF

    python3 -c '
import base64
csv_data = b"service_name,language,source_file,version_expr\nauth_svc,c,auth_svc.c,(10+4)*2-5\ndata_svc,go,data_svc.go,100/(4+1)\n"
encoded = base64.b32encode(csv_data)
with open("/home/user/manifest.b32", "wb") as f:
    f.write(encoded)
'

    chmod -R 777 /home/user
