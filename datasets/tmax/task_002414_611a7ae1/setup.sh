#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest

    # Create dummy whisper CLI to avoid huge model downloads and timeouts
    cat << 'EOF' > /usr/local/bin/whisper
#!/bin/bash
echo "Please apply a final modulus of seven hundred and thirty three to all evaluated expressions."
EOF
    chmod +x /usr/local/bin/whisper

    # Create directories and files
    mkdir -p /app
    touch /app/transmission.wav

    mkdir -p /home/user/aud-eval
    cat << 'EOF' > /home/user/aud-eval/main.go
package main
import "fmt"
func main() {
    fmt.Println("Sequential baseline")
}
EOF

    cat << 'EOF' > /home/user/aud-eval/parser.go
package main
func parse() {}
EOF

    cat << 'EOF' > /home/user/aud-eval/equations.txt
(1+1) | 98
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
