#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang locales tzdata
    pip3 install pytest

    locale-gen en_US.UTF-8

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/app
    mkdir -p /home/user/config

    cat << 'EOF' > /home/user/app/mailer.go
package main

import (
	"fmt"
	"os"
	"time"
)

func main() {
	repDir := "/tmp/default_reports"
	envDir := os.Getenv("REPORTS_DIR")
	if envDir != "" {
		repDir := envDir // BUG: shadowed variable
		fmt.Printf("Configured dir: %s\n", repDir)
	}

	err := os.MkdirAll(repDir, 0755)
	if err != nil {
		panic(err)
	}

	f, err := os.Create(repDir + "/report.txt")
	if err != nil {
		panic(err)
	}
	defer f.Close()

	t := time.Now().Format("2006-01-02 15:04:05 MST")
	fmt.Fprintf(f, "Time: %s\nLocale: %s\nPort: %s\n", t, os.Getenv("LC_ALL"), os.Getenv("SMTP_PORT"))
}
EOF

    cat << 'EOF' > /home/user/run_job.sh
#!/bin/bash
REPORTS_DIR=/home/user/reports
TZ=America/Los_Angeles
LC_ALL=en_US.UTF-8
SMTP_PORT=2525

# Variables are missing the required keyword
cd /home/user/app && go run mailer.go
EOF
    chmod +x /home/user/run_job.sh

    chmod -R 777 /home/user
