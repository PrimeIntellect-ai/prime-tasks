#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest Pillow

    mkdir -p /app /home/user/app_logs

    # Generate spec.png using Python
    cat << 'EOF' > /tmp/gen_img.py
from PIL import Image, ImageDraw, ImageFont
text = """API Service Specification
Listen Port: 8081
Auth User: netadmin
Auth Pass: pWd99xyz
Log File: /home/user/app_logs/service.log"""
img = Image.new('RGB', (400, 200), color=(255, 255, 255))
d = ImageDraw.Draw(img)
d.text((10, 10), text, fill=(0, 0, 0))
img.save('/app/spec.png')
EOF
    python3 /tmp/gen_img.py
    rm /tmp/gen_img.py

    cat << 'EOF' > /home/user/service.go
package main

import (
	"log"
	"net/http"
	"os"
)

func main() {
	// Bug: Relative path causes issues depending on where start.sh runs it from
	f, err := os.OpenFile("service.log", os.O_RDWR|os.O_CREATE|os.O_APPEND, 0666)
	if err != nil {
		log.Fatalf("error opening file: %v", err)
	}
	defer f.Close()
	log.SetOutput(f)

	http.HandleFunc("/ping", func(w http.ResponseWriter, r *http.Request) {
        // Bug: Missing Basic Auth check
		w.Write([]byte("pong"))
	})

    // Bug: Hardcoded wrong port
	log.Println("Starting server on :8080")
	if err := http.ListenAndServe("127.0.0.1:8080", nil); err != nil {
		log.Fatal(err)
	}
}
EOF

    cat << 'EOF' > /home/user/start.sh
#!/bin/bash
cd /tmp
nohup go run /home/user/service.go > /dev/null 2>&1 &
EOF
    chmod +x /home/user/start.sh

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
