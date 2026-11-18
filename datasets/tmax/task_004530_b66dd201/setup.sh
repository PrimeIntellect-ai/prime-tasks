#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_tickets.txt
Ticket: TKT-101
Contact: alice@example.com
Description: The billing page is not loading for me. It just spins.
===
Ticket: TKT-102
Contact: bob@test.com
Description: How do I change my avatar?
===
Ticket: TKT-103
Contact: alice@example.com
Description: the billing page is not loading for me. it just spins.
===
Ticket: TKT-104
Contact: charlie@domain.com
Description: The billing page is not loading for me. It just spins forever.
===
Ticket: TKT-105
Contact: dave@test.com
Description: I am trying to update my profile picture but the upload fails.
===
Ticket: TKT-106
Contact: eve@test.com
Description: How do I change my avatar?
===
Ticket: TKT-107
Contact: frank@test.com
Description: System crashes when I export to PDF.
===
Ticket: TKT-108
Contact: george@test.com
Description: System crashes when I export to PDF.
===
EOF

    chmod -R 777 /home/user
