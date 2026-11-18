#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip wget
    pip3 install pytest aiosmtpd==1.4.3

    mkdir -p /app
    wget https://files.pythonhosted.org/packages/source/a/aiosmtpd/aiosmtpd-1.4.3.tar.gz
    tar -xzf aiosmtpd-1.4.3.tar.gz
    mv aiosmtpd-1.4.3 /app/aiosmtpd
    rm aiosmtpd-1.4.3.tar.gz

    # Apply perturbation
    sed -i '/async def smtp_DATA(self, arg):/a \ \ \ \ \ \ \ \ await asyncio.sleep(0.5)' /app/aiosmtpd/aiosmtpd/smtp.py

    cat << 'EOF' > /app/run_server.py
import sys
sys.path.insert(0, '/app/aiosmtpd')
import asyncio
from aiosmtpd.controller import Controller

class CustomHandler:
    async def handle_DATA(self, server, session, envelope):
        return '250 Message accepted for delivery'

if __name__ == '__main__':
    handler = CustomHandler()
    controller = Controller(handler, hostname='127.0.0.1', port=8025)
    controller.start()
    try:
        asyncio.get_event_loop().run_forever()
    except KeyboardInterrupt:
        pass
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
