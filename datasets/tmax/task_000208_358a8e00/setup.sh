#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_dataset.txt
---RECORD---
ID: 1
Date: 2023-01-01
Text: Hello
World
---RECORD---
ID: 2
Date: 2023-01-02
Text: Good
morning
everyone
---RECORD---
ID: 3
Text: No date here
---RECORD---
ID: 4
Date: 2023-01-04
Text: Yes
---RECORD---
ID: 5
Date: 2023-01-05
---RECORD---
ID: 6
Date: 2023-01-06
Text: The final
valid
record.
EOF

    chmod -R 777 /home/user
