#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/clibs

    touch /home/user/clibs/libmatrix.so.1.0.0
    touch /home/user/clibs/libmatrix.so.1.4.9
    touch /home/user/clibs/libmatrix.so.1.6.2
    touch /home/user/clibs/libmatrix.so.1.8.5
    touch /home/user/clibs/libmatrix.so.2.0.1
    touch /home/user/clibs/libmatrix.so.2.1.0

    cat << 'EOF' > /home/user/math_runner
#!/bin/bash
if [ ! -L /home/user/clibs/libmatrix.so ]; then
    echo "Error: libmatrix.so symlink not found."
    exit 1
fi

TARGET=$(readlink /home/user/clibs/libmatrix.so)
if [ "$TARGET" != "libmatrix.so.1.8.5" ] && [ "$TARGET" != "/home/user/clibs/libmatrix.so.1.8.5" ]; then
    echo "Error: Linked to incorrect version: $TARGET"
    exit 1
fi

if [[ ":$LD_LIBRARY_PATH:" != *":/home/user/clibs:"* ]]; then
    echo "Error: LD_LIBRARY_PATH not set correctly."
    exit 1
fi

# Simulate concurrent scrambled output
cat << 'LOG' > /home/user/output_v1.log
[Worker 4] Schema=v1 | Determinant=14.22 | MatrixID=1004
[Worker 1] Schema=v1 | Determinant=-99.50 | MatrixID=1001
[Worker 2] Schema=v1 | Determinant=42.00 | MatrixID=1002
[Worker 4] Schema=v1 | Determinant=8.11 | MatrixID=1005
[Worker 3] Schema=v1 | Determinant=105.7 | MatrixID=1003
LOG
echo "Success: Log written."
EOF

    chmod +x /home/user/math_runner

    chmod -R 777 /home/user
