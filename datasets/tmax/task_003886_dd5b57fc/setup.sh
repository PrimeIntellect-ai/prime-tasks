#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip qrencode ffmpeg golang zbar-tools gawk
pip3 install pytest

mkdir -p /app
mkdir -p /home/user/manifests
mkdir -p /home/user/active_mounts

# Generate the video with a QR code
qrencode -o /tmp/qr.png "TARGET_DIR=/home/user/operator_data;BACKING_SIZE=1024"
ffmpeg -loop 1 -i /tmp/qr.png -c:v libx264 -t 3 -pix_fmt yuv420p -vf scale=320:320 /app/operator_demo.mp4

# Generate 10000 manifests efficiently to avoid build timeout
gawk 'BEGIN {
  for (i=1; i<=10000; i++) {
    ns = "ns-" (i % 20)
    vol = "vol-" i
    file = "/home/user/manifests/manifest_" i ".yaml"
    print "apiVersion: v1\nkind: PersistentVolume\nmetadata:\n  name: " vol "\n  namespace: " ns > file
    close(file)
  }
}'

# Create the broken bash script
cat <<'EOF' > /home/user/run_operator.sh
#!/bin/bash
# Cron runs us with PATH=/bin
./operator
EOF
chmod +x /home/user/run_operator.sh

# Create the slow Go program
cat <<'EOF' > /home/user/operator.go
package main

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"
)

func main() {
	targetDir := os.Getenv("TARGET_DIR")
	if targetDir == "" {
		targetDir = "/tmp/wrong_dir"
	}

	files, _ := filepath.Glob("/home/user/manifests/*.yaml")
	fstab, _ := os.OpenFile("/home/user/fstab.mock", os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0644)
	defer fstab.Close()

	for _, file := range files {
		// Simulate slow sequential I/O / parsing processing
		time.Sleep(1 * time.Millisecond)

		data, _ := os.ReadFile(file)
		lines := strings.Split(string(data), "\n")
		var ns, vol string
		for _, line := range lines {
			if strings.Contains(line, "namespace:") {
				ns = strings.TrimSpace(strings.Split(line, ":")[1])
			}
			if strings.Contains(line, "name:") {
				vol = strings.TrimSpace(strings.Split(line, ":")[1])
			}
		}

		outDir := filepath.Join(targetDir, ns)
		os.MkdirAll(outDir, 0755)
		imgPath := filepath.Join(outDir, vol+".img")
		os.WriteFile(imgPath, make([]byte, 1024), 0644)

		fstab.WriteString(fmt.Sprintf("%s /mnt/simulated/%s/%s ext4 loop,defaults 0 0\n", imgPath, ns, vol))
	}
}
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
