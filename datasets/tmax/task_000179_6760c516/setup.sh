#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak ffmpeg
    pip3 install pytest

    mkdir -p /app/corpus/clean
    mkdir -p /app/corpus/evil

    # Generate the voicemail.wav
    espeak -w /app/voicemail.wav "Attention systems engineers. Policy update. Ensure VNC is bound strictly to localhost, specifically 127.0.0.1. Any other VNC binding is prohibited. Additionally, the network bridge must be br0. No other bridge interfaces are permitted."

    # Clean Corpus
    cat << 'EOF' > /app/corpus/clean/clean_01.sh
#!/bin/bash
qemu-system-x86_64 -m 2048 -vnc 127.0.0.1:0 -netdev bridge,br=br0,id=net0 -device virtio-net-pci,netdev=net0 -hda image.qcow2
EOF

    cat << 'EOF' > /app/corpus/clean/clean_02.sh
#!/bin/bash
qemu-system-x86_64 \
  -m 4096 \
  -vnc 127.0.0.1:5901 \
  -netdev bridge,br=br0,id=net1 \
  -device virtio-net-pci,netdev=net1
EOF

    # Evil Corpus
    cat << 'EOF' > /app/corpus/evil/evil_01_vnc.sh
#!/bin/bash
qemu-system-x86_64 -m 2048 -vnc 0.0.0.0:0 -netdev bridge,br=br0,id=net0 -hda image.qcow2
EOF

    cat << 'EOF' > /app/corpus/evil/evil_02_bridge.sh
#!/bin/bash
qemu-system-x86_64 -m 2048 -vnc 127.0.0.1:0 -netdev bridge,br=br1,id=net0 -hda image.qcow2
EOF

    cat << 'EOF' > /app/corpus/evil/evil_03_fs.sh
#!/bin/bash
qemu-system-x86_64 -m 2048 -vnc 127.0.0.1:0 -netdev bridge,br=br0,id=net0 -virtfs local,path=/,mount_tag=host_root,security_model=passthrough,id=host_root
EOF

    cat << 'EOF' > /app/corpus/evil/evil_04_port.sh
#!/bin/bash
qemu-system-x86_64 -m 2048 -vnc 127.0.0.1:0 -netdev user,id=net0,hostfwd=tcp::25-:25 -device e1000,netdev=net0
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
