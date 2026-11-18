#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip expect gcc libc6-dev
    pip3 install pytest

    mkdir -p /home/user/bin /home/user/spool

    cat << 'EOF' > /home/user/bin/interactive_setup
#!/bin/bash
read -p "Enter Admin Email: " admin
read -p "Enter SMTP Port: " port
read -p "Enter Deployment Stage (staging/prod): " stage

echo "ADMIN=$admin" > /home/user/mailer_config.txt
echo "PORT=$port" >> /home/user/mailer_config.txt
echo "STAGE=$stage" >> /home/user/mailer_config.txt
echo "Config written to /home/user/mailer_config.txt"
EOF
    chmod +x /home/user/bin/interactive_setup

    cat << 'EOF' > /home/user/spool/msg1.txt
Subject: Hello
To: list@backup.local
From: sender@domain.com
EOF

    cat << 'EOF' > /home/user/spool/msg2.txt
Subject: Spam
To: someone.else@domain.com
From: spammer@spam.com
EOF

    cat << 'EOF' > /home/user/spool/msg3.txt
To: list@backup.local
Subject: Another message
EOF

    cat << 'EOF' > /home/user/spool/msg4.txt
Subject: Broken message without To header
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
