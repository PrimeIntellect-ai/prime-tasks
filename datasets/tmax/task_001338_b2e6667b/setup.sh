#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/config_backups

    python3 -c "
import os
os.makedirs('/home/user/config_backups', exist_ok=True)
with open('/home/user/config_backups/router_v1.bin', 'wb') as f:
    f.write(b'\xCF\xFA\xED\xFE\x00\x01\x02\x03')
with open('/home/user/config_backups/firewall_v2.bin', 'wb') as f:
    f.write(b'\xCF\xFA\xED\xFE\x00\x11\x22\x33')
with open('/home/user/config_backups/switch_v1.bin', 'wb') as f:
    f.write(b'\xCF\xFA\xED\xFE\xAA\xBB\xCC\xDD')
with open('/home/user/config_backups/router_v2.bin', 'wb') as f:
    f.write(b'\xDE\xAD\xBE\xEF\x00\x01\x02\x03')
with open('/home/user/config_backups/proxy_v1.bin', 'wb') as f:
    f.write(b'\xCF\xFA\xED\xFD\x00\x00\x00\x00')
"

    cat << 'EOF' > /home/user/change_history.log
Ticket: TKT-1001
Author: Alice
Files:
 - router_v1.bin
 - router_v2.bin
Status: Approved
---
Ticket: TKT-1002
Author: Bob
Files:
 - firewall_v2.bin
 - missing_fw.bin
Status: Pending
---
Ticket: TKT-1003
Author: Charlie
Files:
 - db_config.bin
Status: Rejected
---
Ticket: TKT-1004
Author: Dave
Files:
 - switch_v1.bin
 - proxy_v1.bin
Status: Approved
---
EOF

    chmod -R 777 /home/user
