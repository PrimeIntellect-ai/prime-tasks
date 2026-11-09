#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user

    cat << 'EOF' > /home/user/loc_events.tsv
2023-10-05T10:00:00Z	bob.smith@trans.com	JA	こんにちは世界
2023-10-01T08:30:00Z	alice.j@corp.org	AR	مرحبا بالعالم
2023-10-02T09:15:00Z	carlos.m@agency.net	ES	Hola Mundo
2023-10-03T11:45:00Z	yuri.v@trans.com	RU	Привет мир
2023-10-06T14:20:00Z	alice.j@corp.org	AR	صباح الخير
2023-10-07T16:00:00Z	zack@freelance.io	ES	Buenos días
2023-10-08T09:00:00Z	bob.smith@trans.com	JA	おはようございます
2023-10-04T13:10:00Z	yuri.v@trans.com	RU	Добрый день
2023-10-09T10:00:00Z	carlos.m@agency.net	ES	Buenas noches
2023-10-10T11:00:00Z	test@test.com	FR	Bonjour
EOF

    chmod -R 777 /home/user
