#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    export TZ=UTC
    apt-get update && apt-get install -y python3 python3-pip espeak tzdata
    pip3 install pytest

    # Ensure container timezone is UTC so that touch and python tests align
    ln -fs /usr/share/zoneinfo/UTC /etc/localtime
    dpkg-reconfigure --frontend noninteractive tzdata

    mkdir -p /app/config /app/logs /app/recordings /app/archive

    cat << 'EOF' > /app/config/backup.ini
[Network]
Timeout=300
[Archival]
TargetEventType=CRITICAL_THERMAL
Retention=365
EOF

    cat << 'EOF' > /app/logs/system_events.log
[Event ID: 1043]
Date: 2023-10-24 12:15:00
Type: INFO_UPDATE
Details: System nominal

[Event ID: 1044]
Date: 2023-10-24 14:32:00
Type: CRITICAL_THERMAL
Details: Sensor 4 failure detected

[Event ID: 1045]
Date: 2023-10-24 15:00:00
Type: RECOVERY
Details: Cooling restored
EOF

    # Generate synthetic audio with the ground truth text
    espeak -w /app/recordings/incident_809.wav "Warning, temperature in sector four has exceeded critical limits. Initiating emergency shutdown protocol."
    touch -m -t 202310241432.00 /app/recordings/incident_809.wav

    # Generate dummy audio files with different modification times
    espeak -w /app/recordings/incident_808.wav "System nominal."
    touch -m -t 202310241215.00 /app/recordings/incident_808.wav

    espeak -w /app/recordings/incident_810.wav "Cooling restored."
    touch -m -t 202310241500.00 /app/recordings/incident_810.wav

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
