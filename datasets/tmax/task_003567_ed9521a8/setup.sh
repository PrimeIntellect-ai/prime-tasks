#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip coreutils
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/cert_bundle.pem
-----BEGIN CERTIFICATE-----
DUMMYCERTIFICATECONTENT12345
-----END CERTIFICATE-----
EOF

    sha256sum /home/user/cert_bundle.pem > /home/user/cert_hash.sha256

    cat << 'EOF' > /home/user/processor.py
import argparse

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--db-pass', required=True, help='Database password')
    args = parser.parse_args()

    password = args.db_pass

    with open('/home/user/processing.log', 'w') as f:
        f.write(f"Connecting to database with password: {password}\n")
        f.write("Data processing complete.\n")

if __name__ == "__main__":
    main()
EOF
    chmod +x /home/user/processor.py

    cat << 'EOF' > /home/user/legacy_runner.sh
#!/bin/bash
python3 /home/user/processor.py --db-pass SUPER_SECRET_99!
EOF
    chmod +x /home/user/legacy_runner.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
