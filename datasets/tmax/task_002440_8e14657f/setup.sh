#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq patch
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/project/src

    cat << 'EOF' > /home/user/project/config.json
{
  "app": "my_app",
  "credentials": {
    "api_key": "SECRET_12345",
    "password": "supersecretpassword",
    "user": "admin"
  }
}
EOF

    cat << 'EOF' > /home/user/project/src/server.js
const express = require('express');
const app = express();
app.get('/', (req, res) => res.send('Hello'));
app.listen(8080);
EOF

    cat << 'EOF' > /home/user/project/src/app.py
print("Hello world")
EOF

    cat << 'EOF' > /home/user/project/src/leaked_script.py
# old script
API_TOKEN = "SECRET_99999"
print("Doing stuff")
EOF

    cat << 'EOF' > /home/user/project/security.patch
--- src/server.js
+++ src/server.js
@@ -1,4 +1,5 @@
 const express = require('express');
 const app = express();
+app.disable('x-powered-by');
 app.get('/', (req, res) => res.send('Hello'));
 app.listen(8080);
EOF

    chown -R user:user /home/user/project
    chmod -R 777 /home/user
