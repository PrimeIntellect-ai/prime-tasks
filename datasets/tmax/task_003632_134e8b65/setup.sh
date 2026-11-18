#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq espeak
    pip3 install pytest

    mkdir -p /app

    # Create the reference parser
    cat << 'EOF' > /app/reference_parser
#!/bin/bash
while IFS= read -r line || [ -n "$line" ]; do
    if [[ "$line" =~ ^\{.*\}$ ]]; then
        msg=$(echo "$line" | jq -r '.message // "NULL"' 2>/dev/null)
        if [ $? -eq 0 ]; then
            echo "JSON_MSG: $msg"
        else
            echo "JSON_MSG: NULL"
        fi
    elif [[ "$line" =~ ^([GM][0-9]+) ]]; then
        cmd="${BASH_REMATCH[1]}"
        if [ "$cmd" != "M117" ]; then
            echo "GCODE: $cmd"
        fi
    else
        upper=$(echo "$line" | tr '[:lower:]' '[:upper:]')
        echo "TEXT: $upper"
    fi
done < "$1"
EOF
    chmod +x /app/reference_parser

    # Generate the audio memo
    espeak -w /app/project_memo.wav "Hey, it's me. I forgot to put this in the written spec, but when you write the log parser, make sure that any GCode command starting with M117 is completely ignored. Just drop the line entirely and don't output anything for it. Thanks."

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
