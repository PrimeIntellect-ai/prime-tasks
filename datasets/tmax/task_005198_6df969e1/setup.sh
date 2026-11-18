#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Create user
    useradd -m -s /bin/bash user || true

    # Create directories
    mkdir -p /home/user/app_repo/scripts
    mkdir -p /home/user/vault

    # Create secret file
    echo "FLAG{c0mm4nd_1nj3ct10n_m4st3r}" > /home/user/vault/secret.txt

    # Create database.config
    cat << 'EOF' > /home/user/app_repo/database.config
DB_HOST=localhost
SECRET_TOKEN=a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4
DB_PORT=5432
EOF

    # Create api.config
    cat << 'EOF' > /home/user/app_repo/api.config
API_VERSION=v2
SECRET_TOKEN=1234567890abcdef1234567890abcdef
DEBUG=true
EOF

    # Create build.sh
    cat << 'EOF' > /home/user/app_repo/scripts/build.sh
#!/bin/bash
echo "Building project..."
exit 0
EOF

    # Create vulnerable deploy.sh
    cat << 'EOF' > /home/user/app_repo/scripts/deploy.sh
#!/bin/bash
while getopts "e:" opt; do
  case $opt in
    e) ENV=$OPTARG ;;
  esac
done
eval "echo Starting deployment in environment: $ENV"
EOF

    # Set executable permissions
    chmod +x /home/user/app_repo/scripts/*.sh

    # Generate hashes file
    sha256sum /home/user/app_repo/scripts/build.sh > /home/user/app_repo/hashes.txt
    echo "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855  /home/user/app_repo/scripts/deploy.sh" >> /home/user/app_repo/hashes.txt

    # Set final permissions
    chmod -R 777 /home/user
