#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/raw_data

    cat << 'EOF' > /home/user/raw_data/data01.txt
I love Python programming!
EOF

    cat << 'EOF' > /home/user/raw_data/data02.txt
Some random text.
EOF

    cat << 'EOF' > /home/user/raw_data/data03.txt
Windows is an OS, Linux is too.
EOF

    cat << 'EOF' > /home/user/raw_data/data04.txt
Machine learning is fun.
EOF

    python3 -c "open('/home/user/raw_data/data05.txt', 'wb').write(b'Caf\xe9 and python.')"
    python3 -c "open('/home/user/raw_data/data06.txt', 'wb').write(b'A\xe7ai bowl is good.')"

    cat << 'EOF' > /home/user/raw_data/data07.txt
Data science using python.
EOF

    cat << 'EOF' > /home/user/raw_data/data08.txt
Just another text.
EOF

    python3 -c "open('/home/user/raw_data/data09.txt', 'wb').write(b'M\xebre text for linux.')"

    cat << 'EOF' > /home/user/raw_data/data10.txt
End of dataset.
EOF

    chmod -R 777 /home/user
