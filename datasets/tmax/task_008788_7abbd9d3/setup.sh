#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/setup_csv.py
import csv
with open('/home/user/raw_locales.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['timestamp', 'msg_id', 'locale', 'translation'])
    writer.writerow(['2023-10-01T10:00:00', 'greeting', 'en', 'Hello\nWorld'])
    writer.writerow(['2023-10-01T10:05:00', 'greeting', 'es', 'Hola\nMundo'])
    writer.writerow(['2023-10-02T10:00:00', 'farewell', 'en', 'Goodbye'])
    writer.writerow(['2023-10-02T10:05:00', 'farewell', 'es', 'Adios'])
    writer.writerow(['2023-10-02T11:00:00', 'farewell', 'es', 'Adiós'])
    writer.writerow(['2023-11-01T10:00:00', 'test1', 'en', 'Test'])
    writer.writerow(['2023-11-01T10:05:00', 'test1', 'es', 'Prueba'])
    writer.writerow(['2023-11-01T10:10:00', 'test2', 'en', 'Test'])
    writer.writerow(['2023-11-01T10:15:00', 'test2', 'es', 'Ensayo']) 
    writer.writerow(['2023-12-01T10:15:00', 'orphan', 'es', 'Solo']) 
EOF
    python3 /home/user/setup_csv.py
    rm /home/user/setup_csv.py

    chmod -R 777 /home/user
