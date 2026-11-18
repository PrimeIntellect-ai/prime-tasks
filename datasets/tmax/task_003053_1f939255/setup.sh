#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Install required packages
    apt-get install -y g++ socat python3-aiosmtpd

    # Create the user and home directory
    useradd -m -s /bin/bash user || true
    mkdir -p /home/user

    # Create the mock_smtp.py script
    cat << 'EOF' > /home/user/mock_smtp.py
#!/usr/bin/env python3
import asyncio
from aiosmtpd.controller import Controller

class CustomHandler:
    async def handle_DATA(self, server, session, envelope):
        with open('/home/user/alert_emails.log', 'a') as f:
            f.write(envelope.content.decode('utf8', errors='replace') + "\n")
        return '250 Message accepted for delivery'

if __name__ == '__main__':
    controller = Controller(CustomHandler(), hostname='127.0.0.1', port=8025)
    controller.start()
    try:
        asyncio.get_event_loop().run_forever()
    except KeyboardInterrupt:
        pass
EOF
    chmod +x /home/user/mock_smtp.py

    # Set permissions
    chmod -R 777 /home/user
