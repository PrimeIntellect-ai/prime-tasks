#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/legacy_builds

    cat << 'EOF' > /home/user/legacy_builds/app.bld
TARGET arm64
DEFINE OS linux
EMIT base_binary
IF OS == linux
  EMIT linux_bindings.so
ENDIF
IF OS == windows
  EMIT win_bindings.dll
ENDIF
EOF

    cat << 'EOF' > /home/user/legacy_builds/tools.bld
TARGET x86_64
DEFINE DEBUG true
EMIT tool_main
IF DEBUG == true
  EMIT debug_symbols.pdb
ENDIF
IF DEBUG == false
  EMIT release_notes.txt
ENDIF
EOF

    cat << 'EOF' > /home/user/legacy_builds/utils.bld
DEFINE LANG python
EMIT wrapper.py
EOF

    chmod -R 777 /home/user
