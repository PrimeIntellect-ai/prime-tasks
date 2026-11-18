#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip ffmpeg zbar-tools qrencode imagemagick openssh-server golang-go
pip3 install pytest requests

mkdir -p /app
mkdir -p /tmp/qrs

# Generate QR codes for the passphrase chunks
qrencode -s 10 -o /tmp/qrs/qr_01.png "SuperSecret"
qrencode -s 10 -o /tmp/qrs/qr_02.png "Passphrase"
qrencode -s 10 -o /tmp/qrs/qr_03.png "123!"

# Pad images to the same size to avoid ffmpeg errors
mogrify -gravity center -background white -extent 500x500 /tmp/qrs/qr_*.png

# Create the video
ffmpeg -framerate 1 -pattern_type glob -i '/tmp/qrs/qr_*.png' -c:v libx264 -r 30 -pix_fmt yuv420p /app/key_video.mp4

# Setup SSH server
mkdir -p /run/sshd
useradd -m -s /bin/bash admin
echo "admin:admin" | chpasswd

ssh-keygen -t ed25519 -f /app/admin_key -N "SuperSecretPassphrase123!" -q
mkdir -p /home/admin/.ssh
cp /app/admin_key.pub /home/admin/.ssh/authorized_keys
chown -R admin:admin /home/admin/.ssh
chmod 700 /home/admin/.ssh
chmod 600 /home/admin/.ssh/authorized_keys
sed -i 's/#Port 22/Port 2222/' /etc/ssh/sshd_config

# Create vulnerable Go server
cat << 'EOF' > /tmp/server.go
package main
import "net/http"
func main() {
    http.HandleFunc("/redirect", func(w http.ResponseWriter, r *http.Request) {
        path := r.URL.Query().Get("path")
        target := "http://super-secret-backend.local/" + path
        http.Redirect(w, r, target, http.StatusFound)
    })
    http.ListenAndServe(":8080", nil)
}
EOF
go build -o /opt/vulnerable_server /tmp/server.go

# Create the verifier script
cat << 'EOF' > /verify.py
import subprocess
import time
import requests

def main():
    try:
        proc = subprocess.Popen(["/home/user/patched_server"])
        time.sleep(1)
        success = 0
        for i in range(10):
            try:
                resp = requests.get(f"http://localhost:8080/redirect?path=test{i}", allow_redirects=False)
                if resp.headers.get("Location") == f"http://redacted-secure-domain.com/test{i}":
                    success += 1
            except Exception:
                pass
        proc.kill()
        print(success / 10.0)
    except Exception:
        print(0.0)

if __name__ == "__main__":
    main()
EOF
chmod +x /verify.py

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
