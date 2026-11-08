#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc gawk sed tar
    pip3 install pytest

    mkdir -p /app/mail_spool /app/backups /app/logs

    cat << 'EOF' > /app/passwd
alice:x:1000:1000:Alice,,,:/home/alice:/bin/bash
bob:x:1001:1001:Bob,,,:/home/bob:/bin/bash
charlie:x:1002:1002:Charlie,,,:/home/charlie:/bin/bash
EOF

    cat << 'EOF' > /app/smtp_mock.py
import smtpd, asyncore, os, time
class CustomSMTPServer(smtpd.SMTPServer):
    def process_message(self, peer, mailfrom, rcpttos, data, **kwargs):
        with open(f"/app/mail_spool/{time.time()}.eml", "wb") as f:
            f.write(data)
server = CustomSMTPServer(('127.0.0.1', 2525), None)
asyncore.loop()
EOF

    cat << 'EOF' > /app/generate_report.sh
#!/bin/bash
USER=$1
# Bug: using wrong delimiter and wrong field
HOMEDIR=$(grep "^$USER:" /app/passwd | awk -F';' '{print $2}')
echo "User $USER has home $HOMEDIR"
EOF
    chmod +x /app/generate_report.sh

    cat << 'EOF' > /app/cron_backup.sh
#!/bin/bash
# Bug: BACKUP_DIR is not defined, defaults to root or /tmp if we fallback
DEST=${BACKUP_DIR:-/tmp}/backup_$(date +%s).tar.gz
tar -czf $DEST /app/passwd 2>/dev/null
EOF
    chmod +x /app/cron_backup.sh

    cat << 'EOF' > /app/account_daemon.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <arpa/inet.h>

int main() {
    // Agent must implement socket binding on 8888, reading "REPORT <user>", 
    // popen() on generate_report.sh, and socket connection to 2525 (SMTP).
    return 0;
}
EOF

    # Wrapper to start background services during initial state tests
    if [ -f /usr/local/bin/pytest ]; then
        mv /usr/local/bin/pytest /usr/local/bin/pytest_orig
        cat << 'EOF' > /usr/local/bin/pytest
#!/bin/bash
python3 /app/smtp_mock.py >/dev/null 2>&1 &
(while true; do env -i bash /app/cron_backup.sh; sleep 5; done) >/dev/null 2>&1 &
sleep 1
exec /usr/local/bin/pytest_orig "$@"
EOF
        chmod +x /usr/local/bin/pytest
    fi

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
