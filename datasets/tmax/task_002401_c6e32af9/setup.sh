#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip xxd
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.sh
#!/bin/bash
mkdir -p /home/user/dataset/exp_a
mkdir -p /home/user/dataset/exp_b/nested

# Create infinite symlink loops
ln -s /home/user/dataset /home/user/dataset/exp_a/loop_to_root
ln -s /home/user/dataset/exp_b /home/user/dataset/exp_b/nested/loop_to_b

# Create an ELF file (copy bash or something simple, or just write magic bytes)
printf '\x7F\x45\x4C\x46\x02\x01\x01\x00' > /home/user/dataset/binary_tool
printf '\x7F\x45\x4C\x46\x01\x02\x01\x00' > /home/user/dataset/exp_a/helper_bin

# Create WAL files
printf '\x37\x7F\x06\x82\x00\x00\x00\x00' > /home/user/dataset/exp_b/db.wal
printf '\x37\x7F\x06\x83\x00\x00\x00\x00' > /home/user/dataset/exp_a/cache.wal

# Create GCODE files
printf ';FLAVOR:Marlin\nG1 X10 Y10 Z10\n' > /home/user/dataset/print_1.gcode
printf ';FLAVOR:RepRap\nM104 S200\n' > /home/user/dataset/exp_b/nested/print_2.gcode

# Create UNKNOWN files
printf 'Just a regular text file.\n' > /home/user/dataset/notes.txt
printf '\x00\x00\x00\x00' > /home/user/dataset/exp_b/empty.dat
# File with similar but wrong header
printf '; FLAVOR:Marlin\n' > /home/user/dataset/exp_a/broken.gcode

EOF

    bash /tmp/setup.sh
    rm /tmp/setup.sh

    chown -R user:user /home/user/dataset
    chmod -R 777 /home/user
