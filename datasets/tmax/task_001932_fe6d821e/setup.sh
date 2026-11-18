#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc systemd
    pip3 install pytest

    groupadd finops
    useradd -m -s /bin/bash user || true
    usermod -aG finops user

    mkdir -p /home/user/src \
             /home/user/bin \
             /home/user/billing_reports \
             /home/user/archives \
             /home/user/run \
             /home/user/logs \
             /home/user/.config/systemd/user

    touch /home/user/billing_reports/aws_march.csv
    touch /home/user/billing_reports/gcp_march.csv

    cat << 'EOF' > /home/user/src/finops_backup.c
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <sys/types.h>
#include <grp.h>
#include <sys/stat.h>

int main() {
    // Check if mailer socket exists
    struct stat buffer;   
    if (stat("/home/user/run/mailer.sock", &buffer) != 0) {
        fprintf(stderr, "Error: Mailer socket not found. Is local-mailer running?\n");
        return 1;
    }

    // Perform backup
    int ret = system("tar -czf /home/user/archives/reports.tar.gz -C /home/user/billing_reports .");
    if (ret != 0) {
        fprintf(stderr, "Error: Tar command failed.\n");
        return 2;
    }

    // Write success log
    FILE *f = fopen("/home/user/logs/backup_success.log", "w");
    if (f) {
        fprintf(f, "FinOps Backup Completed and Notification Sent\n");
        fclose(f);
    }
    return 0;
}
EOF

    cat << 'EOF' > /home/user/.config/systemd/user/local-mailer.service
[Unit]
Description=Local Mock Mailer

[Service]
ExecStartPre=/usr/bin/touch /home/user/run/mailer.sock
ExecStart=/usr/bin/tail -f /dev/null
ExecStopPost=/usr/bin/rm -f /home/user/run/mailer.sock
EOF

    cat << 'EOF' > /home/user/.config/systemd/user/finops-backup.service
[Unit]
Description=FinOps Backup Service

[Service]
Type=oneshot
ExecStart=/home/user/bin/finops_backup
EOF

    chmod -R 777 /home/user
