#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip wget
    pip3 install pytest

    # Create app directory
    mkdir -p /app
    cd /app

    # Download and extract PyJWT 2.8.0
    wget https://files.pythonhosted.org/packages/source/P/PyJWT/PyJWT-2.8.0.tar.gz
    tar xzf PyJWT-2.8.0.tar.gz
    rm PyJWT-2.8.0.tar.gz

    # Tamper with the HMAC verification logic
    sed -i 's/return hmac.compare_digest(sig, self.sign(msg, key))/return False # TAMPERED/g' /app/PyJWT-2.8.0/jwt/algorithms.py

    # Create the generate_key.py script
    cat << 'EOF' > /app/generate_key.py
def get_master_key():
    parts = ["S3cr3t", "C0mpl1anc3", "K3y!"]
    return "".join(parts)
EOF

    # Compile to bytecode and remove the source
    python3 -c "import py_compile; py_compile.compile('/app/generate_key.py', cfile='/app/generate_key.pyc')"
    rm /app/generate_key.py

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
