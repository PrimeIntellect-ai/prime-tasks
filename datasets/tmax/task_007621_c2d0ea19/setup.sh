#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    mkdir -p /home/user
    cat << 'EOF' > /home/user/raw_docs.log
Starting documentation build...
Building chapter1.md...
[DOC-ERROR]
File: chapter1.md
Line: 45
Message: Broken link to 'intro'
Severity: WARN
[END-ERROR]
Building chapter2.md...
[DOC-ERROR]
File: chapter2.md
Line: 12
Message: Missing image resource 'arch.png'
Severity: FATAL
[END-ERROR]
Processing API references...
[DOC-ERROR]
File: api.md
Line: 99
Message: Syntax error in code block
Severity: FATAL
[END-ERROR]
Build finished with errors.
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
