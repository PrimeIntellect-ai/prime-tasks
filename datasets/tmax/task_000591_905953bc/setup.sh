#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/webapp

    cat << 'EOF' > /home/user/webapp/index.html
<html>
<body>
<script src="app.js"></script>
</body>
</html>
EOF

    cat << 'EOF' > /home/user/webapp/safe.html
<html>
<body>
<script nonce="rAnd0m" src="app.js"></script>
</body>
</html>
EOF

    cat << 'EOF' > /home/user/webapp/config.php
<?php
$cmd = $_GET['cmd'];
eval($cmd);
?>
EOF
    chmod 777 /home/user/webapp/config.php

    cat << 'EOF' > /home/user/webapp/data.txt
user data
EOF
    chmod 666 /home/user/webapp/data.txt

    cat << 'EOF' > /home/user/webapp/app.js
console.log("Hello, world!");
EOF

    chown -R user:user /home/user
    chmod -R 777 /home/user
