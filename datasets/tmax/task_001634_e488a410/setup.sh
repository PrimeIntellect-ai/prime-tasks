#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip expect
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/sg-console.sh
#!/bin/bash
echo "Secure Gateway Console"
read -p "Username: " user
read -sp "Password: " pass
echo ""
if [ "$user" != "admin" ] || [ "$pass" != "secret123" ]; then
    echo "Access denied."
    exit 1
fi
echo "Access granted."
while true; do
    read -p "SG> " cmd arg1 arg2
    case "$cmd" in
        "route")
            if [ "$arg1" == "add" ]; then
                echo "$arg2" >> /home/user/.sg_routes
                echo "Route added."
            fi
            ;;
        "ping")
            if grep -q "$arg1" /home/user/.sg_routes 2>/dev/null; then
                echo "Reply from $arg1"
            else
                echo "Destination unreachable"
            fi
            ;;
        "exit")
            echo "Goodbye."
            exit 0
            ;;
        *)
            echo "Unknown command."
            ;;
    esac
done
EOF
    chmod +x /home/user/sg-console.sh

    cat << 'EOF' > /home/user/routes.txt
10.0.1.0/24 192.168.1.254
172.16.0.0/16 192.168.1.254
192.168.100.0/24 10.0.0.1
EOF

    chmod -R 777 /home/user
