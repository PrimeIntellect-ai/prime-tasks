#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/build_project/src
    mkdir -p /home/user/build_project/.cache/recovery

    # Create the config file in the hidden recovery folder
    cat << 'EOF' > /home/user/build_project/.cache/recovery/config.inc
# Core configuration
BUILD_MODE="production"
OUTPUT_DIR="/home/user/build_project/out"
EOF

    # Create the build script
    cat << 'EOF' > /home/user/build_project/build.sh
#!/bin/bash

if [ ! -f "config.inc" ]; then
    echo "FATAL: config.inc missing. Build cannot proceed."
    exit 1
fi

source config.inc

if [ -z "$ENABLE_STRICT_BUILD" ] || [ "$ENABLE_STRICT_BUILD" != "true" ]; then
    echo "FATAL: ENABLE_STRICT_BUILD environment variable must be set to 'true'."
    exit 1
fi

mkdir -p "$OUTPUT_DIR"

echo "Starting build..."
for file in src/*.txt; do
    filename=$(basename "$file")
    # Vulnerable sed processing that will crash on unescaped slashes or bad quotes
    content=$(cat "$file")

    # This sed command will break if content has a naked / or unclosed regex
    # The error will halt the script due to set -e (if enabled) or just fail
    processed=$(echo "$content" | sed -e "s/TARGET/$content/g" 2>/dev/null)

    if [ $? -ne 0 ]; then
        echo "Build failed processing $filename"
        exit 1
    fi

    echo "$processed" > "$OUTPUT_DIR/$filename"
done

echo "Build complete."
EOF
    chmod +x /home/user/build_project/build.sh

    # Generate 100 valid files
    for i in $(seq -w 1 100); do
        echo "Standard file content $i TARGET" > /home/user/build_project/src/file_$i.txt
    done

    # Inject the poison file
    echo "s/TARGET/UNCLOSED_REGEX" > /home/user/build_project/src/file_073.txt

    chown -R user:user /home/user/build_project
    chmod -R 777 /home/user
