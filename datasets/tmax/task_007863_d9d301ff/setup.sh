#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/calc_service.sh
#!/bin/bash
rm -f /tmp/calc_in /tmp/calc_out
mkfifo /tmp/calc_in /tmp/calc_out

LOG_BUFFER=""

cleanup() {
    rm -f /tmp/calc_in /tmp/calc_out
    exit 0
}
trap cleanup EXIT

# Keep the pipe open for reading by opening a dummy writer
exec 3<> /tmp/calc_in

while read -r cmd n <&3; do
    if [[ "$cmd" == "QUIT" ]]; then
        break
    elif [[ "$cmd" == "fact" ]]; then
        # BUG 1: Formula Error (starts at 0, should be 1)
        result=0
        if [[ $n -eq 0 ]]; then result=1; fi
        for (( i=1; i<=n; i++ )); do
            result=$((result * i))
        done

        # Send result
        echo "$result" > /tmp/calc_out

        # BUG 2: Memory leak
        LOG_BUFFER+="fact $n = $result"$'\n'
        echo -e "$LOG_BUFFER" > /home/user/service.log
    fi
done
EOF

    chmod +x /home/user/calc_service.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
