#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go imagemagick expect tesseract-ocr
    pip3 install pytest

    mkdir -p /app
    mkdir -p /home/user

    # Generate image
    convert -size 800x200 xc:white -fill black -pointsize 18 \
        -draw "text 10,50 'Legacy Backup Algorithm: SHA256'" \
        -draw "text 10,80 'Format: sha256(service_name + \"-\" + date + \"-BKP-\" + salt)'" \
        -draw "text 10,110 'Secret Salt: s@ltY88'" \
        /app/backup_rules.png

    # Create oracle_gen
    cat << 'EOF' > /app/oracle_gen.go
package main
import (
    "crypto/sha256"
    "fmt"
    "os"
)
func main() {
    if len(os.Args) < 3 {
        return
    }
    hash := sha256.Sum256([]byte(os.Args[1] + "-" + os.Args[2] + "-BKP-s@ltY88"))
    fmt.Printf("%x", hash)
}
EOF
    go build -o /app/oracle_gen /app/oracle_gen.go
    rm /app/oracle_gen.go

    # Create submit_backup
    cat << 'EOF' > /app/submit_backup
#!/bin/bash
read -p "Enter service: " svc
read -p "Enter date: " dt
read -p "Proceed? [y/N]: " ans
if [ "$ans" = "y" ]; then
    echo "Done"
    exit 0
else
    exit 1
fi
EOF
    chmod +x /app/submit_backup

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
