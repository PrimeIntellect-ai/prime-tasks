#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Create user
    useradd -m -s /bin/bash user || true

    # Setup task files
    mkdir -p /home/user/webapp

    cat << 'EOF' > /home/user/webapp/checksums.txt
e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855  index.html
e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855  app.js
e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855  config.json
e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855  dashboard.html
e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855  utils.js
EOF

    cat << 'EOF' > /home/user/webapp/index.html
<html>
<body>
  <script>
    document.getElementById("test").innerHTML = window.location.hash;
  </script>
</body>
</html>
EOF

    cat << 'EOF' > /home/user/webapp/app.js
function test(data) {
    eval(data);
}
EOF

    touch /home/user/webapp/config.json

    cat << 'EOF' > /home/user/webapp/dashboard.html
<html>
<head>
  <meta http-equiv="Content-Security-Policy" content="default-src 'self'; script-src 'self' 'unsafe-inline';">
</head>
<body>Dashboard</body>
</html>
EOF

    cat << 'EOF' > /home/user/webapp/utils.js
function add(a, b) {
    return a + b;
}
EOF

    # Ensure /home/user is accessible and writable
    chmod -R 777 /home/user

    # Fix specific permissions required by the task
    chmod o-w /home/user/webapp/app.js
