#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl
    pip3 install pytest

    # Create user
    useradd -m -s /bin/bash user || true

    # Setup task directories and files
    mkdir -p /home/user/app
    mkdir -p /home/user/shared_data
    echo "READY" > /home/user/shared_data/init.txt

    # Create broken symlink
    ln -s /home/user/old_data /home/user/app/data

    # Create the app start script
    cat << 'EOF' > /home/user/app/start.sh
#!/bin/bash
if [ ! -f "/home/user/app/data/init.txt" ]; then
  echo "Error: Application data directory is missing or invalid. Failed to read init.txt."
  exit 1
fi

echo "pong" > /home/user/app/ping
cd /home/user/app && python3 -m http.server 8080 &
echo $! > /home/user/app/app.pid
EOF
    chmod +x /home/user/app/start.sh

    # Create the deploy script
    cat << 'EOF' > /home/user/deploy.sh
#!/bin/bash
echo "Deploying app..."
if [ -f /home/user/app/app.pid ]; then
  kill -9 $(cat /home/user/app/app.pid) 2>/dev/null
  rm /home/user/app/app.pid
fi
/home/user/app/start.sh
if [ $? -eq 0 ]; then
  echo "Application started."
else
  echo "Deployment failed."
  exit 1
fi
EOF
    chmod +x /home/user/deploy.sh

    # Set permissions
    chmod -R 777 /home/user
