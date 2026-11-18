#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/linker_error.log
/usr/bin/ld: ui_module.o: in function `render_screen':
ui_module.c:(.text+0x14): undefined reference to `draw_rect'
/usr/bin/ld: ui_module.c:(.text+0x28): undefined reference to `fill_color'
/usr/bin/ld: network.o: in function `fetch_data':
network.c:(.text+0x50): undefined reference to `ssl_connect'
/usr/bin/ld: network.c:(.text+0x80): undefined reference to `ssl_read'
/usr/bin/ld: core.o: in function `init':
core.c:(.text+0x5): undefined reference to `hardware_init'
collect2: error: ld returned 1 exit status
EOF

    chmod -R 777 /home/user
