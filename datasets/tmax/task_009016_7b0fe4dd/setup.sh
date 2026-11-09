#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest hypothesis

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/nm_output.txt
0000000000001000 0000000000000040 T init_widget
0000000000003000 0000000000000080 W init_widget
0000000000002000 0000000000000010 D global_config
0000000000004000 0000000000000010 D global_config
                 U external_dep
0000000000005000 0000000000000100 T calculate_hash
0000000000006000 0000000000000100 T calculate_hash
0000000000007000 0000000000000020 R const_data
0000000000008000 0000000000000030 R const_data
EOF

    chmod -R 777 /home/user
