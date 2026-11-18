#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/registry.txt
PKG: AppX
VER: 1.0.0
DEPS: LibNet>=2.0.0, LibData==1.5.0
---
PKG: LibNet
VER: 2.1.0
DEPS: LibCore>=1.1.0
---
PKG: LibNet
VER: 1.9.0
DEPS: LibCore>=1.0.0
---
PKG: LibData
VER: 1.5.0
DEPS: LibCore<=1.2.0
---
PKG: LibCore
VER: 1.0.0
DEPS: NONE
---
PKG: LibCore
VER: 1.1.5
DEPS: NONE
---
PKG: LibCore
VER: 1.2.0
DEPS: NONE
---
PKG: LibCore
VER: 1.3.0
DEPS: NONE
---
PKG: UnrelatedPkg
VER: 5.0.0
DEPS: LibCore==1.3.0
---
EOF

    chmod -R 777 /home/user
