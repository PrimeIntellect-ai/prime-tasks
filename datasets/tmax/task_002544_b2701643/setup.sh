#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang expect tar gzip
    pip3 install pytest

    # Set up Go symlink to match the script
    mkdir -p /usr/local/go/bin
    ln -s /usr/bin/go /usr/local/go/bin/go

    # Create user
    useradd -m -s /bin/bash user || true

    # Create directories
    mkdir -p /home/user/users_data
    mkdir -p /home/user/backups
    mkdir -p /home/user/restored_data

    # Create user data files
    echo "alice config" > /home/user/users_data/alice.txt
    echo "bob config" > /home/user/users_data/bob.txt

    # Create backup.go
    cat << 'EOF' > /home/user/backup.go
package main

import (
	"log"
	"os/exec"
)

func main() {
	// The agent needs to change "./users.tar.gz" to "/home/user/backups/users.tar.gz"
	cmd := exec.Command("tar", "-czf", "./users.tar.gz", "-C", "/home/user/users_data", ".")
	if err := cmd.Run(); err != nil {
		log.Fatal(err)
	}
}
EOF

    # Create cron_run.sh
    cat << 'EOF' > /home/user/cron_run.sh
#!/bin/bash
# Simulates a cron job running in a restricted environment
cd /tmp
env -i /usr/local/go/bin/go run /home/user/backup.go
EOF
    chmod +x /home/user/cron_run.sh

    # Create restore.sh
    cat << 'EOF' > /home/user/restore.sh
#!/bin/bash
echo -n "Enter backup file path: "
read filepath
if [ ! -f "$filepath" ]; then
    echo "File not found!"
    exit 1
fi
tar -xzf "$filepath" -C /home/user/restored_data
echo "Restore complete"
EOF
    chmod +x /home/user/restore.sh

    # Set permissions
    chmod -R 777 /home/user
