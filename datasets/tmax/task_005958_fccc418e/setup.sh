#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/docs

    python3 -c "
content = '''===RECORD===
Date: 2020-01-01
Update: Fixed typos in V1 API.
===RECORD===
Date: 2020-02-15
Update: V1 API DEPRECATED.
Please use V2.
===RECORD===
Date: 2021-05-10
Update: Added examples for V2.
===RECORD===
Date: 2021-08-20
Update: The old authentication method is now DEPRECATED
and will be removed in V3.
===RECORD===
'''
with open('/home/user/docs/raw_changelog.dat', 'wb') as f:
    f.write(content.encode('utf-16le'))
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
