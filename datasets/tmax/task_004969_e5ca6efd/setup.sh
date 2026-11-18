#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg socat netcat-openbsd curl
    pip3 install pytest numpy scipy

    mkdir -p /app

    cat << 'EOF' > /app/molecule.pdb
REMARK   1 MOLECULE SETUP
HETATM    1  O   HOH A   1      12.000  15.000  10.000  1.00  0.00           O  
EOF
    for i in $(seq 1 42); do
      printf "ATOM  %5d  CA  ALA A %3d      10.000  10.000  10.000  1.00  0.00           C\n" $i $i >> /app/molecule.pdb
    done
    cat << 'EOF' >> /app/molecule.pdb
HETATM    2  O   HOH A   2      13.000  16.000  11.000  1.00  0.00           O  
END
EOF

    ffmpeg -f lavfi -i "sine=frequency=850:duration=3" -ac 1 -ar 44100 /app/vibration.wav

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
