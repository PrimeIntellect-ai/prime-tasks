#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq
    pip3 install pytest

    # Create the vendored package directory and script
    mkdir -p /app/vendor/bash-router-1.2.0/
    cat << 'EOF' > /app/vendor/bash-router-1.2.0/router.sh
#!/bin/bash
ROUTER_CONFIG_PATH="/etc/bash-router/config"
if [ "$1" == "--health-check" ]; then
    if [ ! -d "$ROUTER_CONFIG_PATH" ]; then
        echo "Error: Config path $ROUTER_CONFIG_PATH does not exist."
        exit 1
    fi
    echo "Health check passed."
    exit 0
fi
EOF
    chmod +x /app/vendor/bash-router-1.2.0/router.sh

    # Create the corpora directories
    mkdir -p /home/user/corpora/clean
    mkdir -p /home/user/corpora/evil

    # Populate Clean Corpus
    echo '{"api_version": 2, "request_type": "query", "payload": {"search_term": "hello world"}}' > /home/user/corpora/clean/1.json
    echo '{"api_version": 3, "request_type": "mutation", "payload": {"user_id": "USR-123", "action_code": 150}}' > /home/user/corpora/clean/2.json
    echo '{"api_version": 5, "request_type": "query", "payload": {"search_term": "short"}}' > /home/user/corpora/clean/3.json
    echo '{"api_version": 2, "request_type": "mutation", "payload": {"user_id": "USR-9999", "action_code": 100}}' > /home/user/corpora/clean/4.json
    echo '{"api_version": 99, "request_type": "mutation", "payload": {"user_id": "USR-A", "action_code": 199}}' > /home/user/corpora/clean/5.json

    # Populate Evil Corpus
    echo '{"api_version": 2, "request_type": "query", "payload": {"search_term": "hello world"}' > /home/user/corpora/evil/1.json
    echo '{"api_version": 1, "request_type": "query", "payload": {"search_term": "hello world"}}' > /home/user/corpora/evil/2.json
    echo '{"request_type": "query", "payload": {"search_term": "hello world"}}' > /home/user/corpora/evil/3.json
    echo '{"api_version": 2, "request_type": "delete", "payload": {"search_term": "hello"}}' > /home/user/corpora/evil/4.json
    echo '{"api_version": 2, "request_type": "query"}' > /home/user/corpora/evil/5.json
    echo '{"api_version": 2, "request_type": "query", "payload": {"search_term": "this search term is definitely way too long to be accepted"}}' > /home/user/corpora/evil/6.json
    echo '{"api_version": 2, "request_type": "query", "payload": {"other": "value"}}' > /home/user/corpora/evil/7.json
    echo '{"api_version": 2, "request_type": "mutation", "payload": {"action_code": 150}}' > /home/user/corpora/evil/8.json
    echo '{"api_version": 2, "request_type": "mutation", "payload": {"user_id": "ADMIN-123", "action_code": 150}}' > /home/user/corpora/evil/9.json
    echo '{"api_version": 2, "request_type": "mutation", "payload": {"user_id": "USR-123", "action_code": 99}}' > /home/user/corpora/evil/10.json
    echo '{"api_version": 2, "request_type": "mutation", "payload": {"user_id": "USR-123", "action_code": 200}}' > /home/user/corpora/evil/11.json
    echo '{"api_version": 2, "request_type": "mutation", "payload": {"user_id": "USR-123", "action_code": "150"}}' > /home/user/corpora/evil/12.json
    echo '{"api_version": 2, "request_type": "query", "payload": {}, "search_term": "hello"}' > /home/user/corpora/evil/13.json
    echo '{"api_version": "2", "request_type": "query", "payload": {"search_term": "hello"}}' > /home/user/corpora/evil/14.json
    echo '{"hello": "world"}' > /home/user/corpora/evil/15.json

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
