#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        ffmpeg \
        golang \
        cron \
        fonts-dejavu-core

    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/telemetry_data/
    mkdir -p /app/bin/

    # Create the oracle
    cat << 'EOF' > /tmp/oracle.go
package main
import (
    "fmt"
    "io/ioutil"
    "os"
    "encoding/hex"
)
func main() {
    input, err := ioutil.ReadAll(os.Stdin)
    if err != nil { os.Exit(1) }
    seed := []byte("A7F9B2C4")
    output := make([]byte, len(input))
    for i := range input {
        output[i] = input[i] ^ seed[i%len(seed)]
    }
    encoded := hex.EncodeToString(output)
    fmt.Printf("Match User iot_admin\n  PubkeyAuthentication yes\n  AuthorizedKeysCommand /usr/bin/validate_payload %s\n  AuthorizedKeysCommandUser nobody\n", encoded)
}
EOF

    go build -o /app/bin/legacy_acl_compiler /tmp/oracle.go
    chmod +x /app/bin/legacy_acl_compiler
    rm /tmp/oracle.go

    # Generate the video artifact
    ffmpeg -f lavfi -i color=c=black:s=640x480:d=10 -vf "drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf:text='BOOTING...':fontcolor=white:fontsize=24:x=(w-text_w)/2:y=(h-text_h)/2:enable='between(t,0,4.8)', drawbox=x=0:y=0:w=640:h=480:color=red@1.0:t=fill:enable='between(t,4.83,4.86)', drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf:text='SEED\: A7F9B2C4':fontcolor=white:fontsize=48:x=(w-text_w)/2:y=(h-text_h)/2:enable='between(t,4.83,4.86)'" -pix_fmt yuv420p /app/boot_diagnostic.mp4

    chown -R user:user /home/user
    chmod -R 777 /home/user
