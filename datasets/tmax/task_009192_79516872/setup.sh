#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/input
    mkdir -p /home/user/output

    python3 -c "
with open('/home/user/template.md', 'w', encoding='utf-8') as f:
    f.write('# Daily Event Report\n')
    f.write('**Date:** {' + '{DATE}' + '}\n')
    f.write('**Total Events:** {' + '{COUNT}' + '}\n\n')
    f.write('## Event Log\n')
    f.write('{' + '{EVENTS}' + '}\n')

events = [
    '1698240000 ||| LOGIN ||| User logged in from café!  ', # 2023-10-25 13:20:00 UTC
    '2023-10-25T14:30:00Z ||| ERROR ||| Disk   full: 99% usage.', # 2023-10-25 14:30:00 UTC
    '10/25/2023 03:45 PM ||| LOGOUT ||| El  niño  logged out...', # 2023-10-25 15:45:00 UTC
    '1698191999 ||| IGNORE ||| Too early...', # 2023-10-24 23:59:59 UTC
    '2023-10-26T00:00:00Z ||| IGNORE ||| Too late...' # 2023-10-26 00:00:00 UTC
]
with open('/home/user/input/sys_events.dat', 'w', encoding='windows-1252') as f:
    for event in events:
        f.write(event + '\n')
"

    chmod -R 777 /home/user
