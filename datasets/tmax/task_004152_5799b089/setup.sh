#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang xxd coreutils
    pip3 install pytest

    mkdir -p /home/user
    cd /home/user

    cat << 'EOSCRIPT' > /tmp/setup.sh
#!/bin/bash
cd /home/user

cat << 'EOF' > original.go
package main
import "fmt"
func main() {
    fmt.Println("Payload executing! Status: IDS_CATCH_ME")
}
EOF

GOOS=linux GOARCH=amd64 go build -o dummy_payload original.go

HEX_DATA=$(xxd -p -c 256 dummy_payload | tr -d '\n')
CHUNK_SIZE=500
TOTAL_LEN=${#HEX_DATA}

> traffic.txt

SEQ=0
for (( i=0; i<$TOTAL_LEN; i+=$CHUNK_SIZE )); do
    CHUNK=${HEX_DATA:$i:$CHUNK_SIZE}
    cat << EOF >> traffic.txt
GET /resource HTTP/1.1
Host: example.com
User-Agent: Mozilla/5.0
Cookie: sequence=$SEQ; data=$CHUNK
Accept: */*

EOF
    SEQ=$((SEQ+1))
done

rm original.go dummy_payload
EOSCRIPT

    bash /tmp/setup.sh
    rm /tmp/setup.sh

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
