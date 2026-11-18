#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git systemd
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/releases/v2
    mkdir -p /home/user/.config/systemd/user/

    git config --global init.defaultBranch main
    git init --bare /home/user/project.git

    echo '#!/bin/bash' > /home/user/project.git/hooks/post-receive
    echo 'echo "Deployed"' >> /home/user/project.git/hooks/post-receive

    ln -s /home/user/releases/v1 /home/user/active-deployment

    cat << 'EOF' > /home/user/.config/systemd/user/git-daemon.service
[Unit]
Description=Dummy Git Daemon

[Service]
ExecStart=/bin/sleep infinity
Restart=always

[Install]
WantedBy=default.target
EOF

    cat << 'EOF' > /home/user/.config/systemd/user/deploy-worker.service
[Unit]
Description=Deploy Worker

[Service]
ExecStart=/bin/sleep infinity
Restart=always

[Install]
WantedBy=default.target
EOF

    # Create a mock systemctl since systemd doesn't run natively in standard Apptainer containers
    cat << 'EOF' > /usr/local/bin/systemctl
#!/bin/bash
if [ "$1" = "--user" ]; then
    shift
    CMD="$1"
    SVC="$2"

    if [ "$CMD" = "is-active" ]; then
        if [ "$SVC" = "git-daemon.service" ]; then
            echo "active"
            exit 0
        elif [ "$SVC" = "deploy-worker.service" ]; then
            if [ -f /tmp/deploy_worker_started ]; then echo "active"; else echo "inactive"; fi
            exit 0
        fi
    elif [ "$CMD" = "is-enabled" ]; then
        if [ "$SVC" = "deploy-worker.service" ]; then
            if [ -f /tmp/deploy_worker_enabled ]; then echo "enabled"; else echo "disabled"; fi
            exit 0
        fi
    elif [ "$CMD" = "start" ]; then
        if [ "$SVC" = "deploy-worker.service" ]; then
            touch /tmp/deploy_worker_started
            exit 0
        fi
    elif [ "$CMD" = "enable" ]; then
        if [ "$SVC" = "deploy-worker.service" ]; then
            touch /tmp/deploy_worker_enabled
            exit 0
        fi
    elif [ "$CMD" = "daemon-reload" ]; then
        exit 0
    elif [ "$CMD" = "show" ]; then
        # Handle: systemctl --user show deploy-worker.service -p After --value
        if [ "$SVC" = "deploy-worker.service" ]; then
            grep "^After=" /home/user/.config/systemd/user/deploy-worker.service | cut -d= -f2
            exit 0
        fi
    fi
fi
/bin/systemctl "$@"
EOF
    chmod +x /usr/local/bin/systemctl

    chmod -R 777 /home/user
    # Ensure hook is not executable after the chmod 777
    chmod -x /home/user/project.git/hooks/post-receive
