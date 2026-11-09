#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip expect
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/service_logs.txt
May 10 10:00:01 server systemd[1]: Starting Mailing List Server...
May 10 10:00:01 server mail-server[1234]: INFO: Loading initial configuration...
May 10 10:00:01 server mail-server[1234]: FATAL ERROR: Configuration incomplete.
May 10 10:00:01 server mail-server[1234]: Details: Admin email must be set to sysadmin@company.local
May 10 10:00:01 server mail-server[1234]: Details: SMTP Port must be configured to 2525
May 10 10:00:01 server systemd[1]: mail-deploy.service: Main process exited, code=exited, status=1/FAILURE
May 10 10:00:01 server systemd[1]: mail-deploy.service: Failed with result 'exit-code'.
EOF

    cat << 'EOF' > /home/user/mail_config_wizard.sh
#!/bin/bash
read -p "Enter Admin Email: " email
read -p "Enter SMTP Port: " port
if [[ -n "$email" && -n "$port" ]]; then
    echo "ADMIN_EMAIL=$email" > /home/user/mail_config.conf
    echo "SMTP_PORT=$port" >> /home/user/mail_config.conf
    echo "Configuration saved successfully."
else
    echo "Error: Inputs cannot be empty."
    exit 1
fi
EOF
    chmod +x /home/user/mail_config_wizard.sh

    chmod -R 777 /home/user
