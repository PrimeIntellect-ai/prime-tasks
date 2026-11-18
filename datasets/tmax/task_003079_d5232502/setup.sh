#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq gawk sqlite3 curl socat
    pip3 install pytest

    # Create datasets
    mkdir -p /home/user/datasets
    cat << 'EOF' > /home/user/datasets/documents.jsonl
{"doc_id": "1", "title": "Intro to AI", "content": "AI is fascinating."}
{"doc_id": "2", "title": "Advanced AI", "content": "Deep learning."}
{"doc_id": "3", "title": "History of Computing", "content": "Charles Babbage."}
{"doc_id": "4", "title": "Programming", "content": "Bash is useful."}
EOF

    cat << 'EOF' > /home/user/datasets/metadata.csv
doc_id,author,timestamp_published
1,Ada,1600000000
2,John Doe,1610000000
3,Ada,1620000000
4,Smith,1630000000
EOF

    # Create vendored package
    mkdir -p /app/bashttpd-1.0/lib

    cat << 'EOF' > /app/bashttpd-1.0/lib/request_parser.sh
#!/bin/bash
# Buggy perturbation: extracts path instead of query string
QUERY_STRING=$(echo "$REQUEST_URI" | cut -d'?' -f1)
export QUERY_STRING
EOF
    chmod +x /app/bashttpd-1.0/lib/request_parser.sh

    cat << 'EOF' > /app/bashttpd-1.0/handle_req.sh
#!/bin/bash
read -r REQUEST_LINE
REQUEST_METHOD=$(echo "$REQUEST_LINE" | awk '{print $1}')
REQUEST_URI=$(echo "$REQUEST_LINE" | awk '{print $2}')
export REQUEST_METHOD REQUEST_URI
source /app/bashttpd-1.0/lib/request_parser.sh
bash "$HANDLER"
EOF
    chmod +x /app/bashttpd-1.0/handle_req.sh

    cat << 'EOF' > /app/bashttpd-1.0/server.sh
#!/bin/bash
PORT=8080
HANDLER=""
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --port) PORT="$2"; shift ;;
        --handler) HANDLER="$2"; shift ;;
    esac
    shift
done
export HANDLER

echo "Starting server on port $PORT with handler $HANDLER"
socat TCP-LISTEN:$PORT,reuseaddr,fork EXEC:"/app/bashttpd-1.0/handle_req.sh"
EOF
    chmod +x /app/bashttpd-1.0/server.sh

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
