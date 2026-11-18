#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tar zip unzip
    pip3 install pytest

    mkdir -p /home/user/extracted_docs
    mkdir -p /home/user/public_docs
    cd /home/user

    # Create source files for archives
    mkdir -p src_core src_api
    echo "core info" > src_core/intro.md
    echo "loop1" > src_core/bad_loop.md
    echo "architecture" > src_core/arch.md
    echo "api reference" > src_api/reference.md
    echo "loop2" > src_api/circular_api.md

    # Create archives
    cd src_core && tar -czf ../core.tar.gz * && cd ..
    cd src_api && zip -r ../api.zip * && cd ..
    tar -czf raw_docs.tar.gz core.tar.gz api.zip
    rm -rf src_core src_api core.tar.gz api.zip

    # Create docs_config.ini
    cat << 'EOF' > /home/user/docs_config.ini
[CoreDocs]
intro.md = /home/user/public_docs/introduction.md
bad_loop.md = /home/user/public_docs/core_loop.md
arch.md = /home/user/public_docs/architecture.md

[APIDocs]
reference.md = /home/user/public_docs/api_ref.md
circular_api.md = /home/user/public_docs/api_loop.md
EOF

    # Create build_errors.log
    cat << 'EOF' > /home/user/build_errors.log
Timestamp: 2023-10-25T10:00:00
File: bad_loop.md
Error: Infinite Symlink Loop
Module: Core
---
Timestamp: 2023-10-25T10:01:00
File: intro.md
Error: Missing Image Reference
Module: Core
---
Timestamp: 2023-10-25T10:02:00
File: circular_api.md
Error: Infinite Symlink Loop
Module: API
---
Timestamp: 2023-10-25T10:03:00
File: arch.md
Error: Formatting Warning
Module: Core
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
