#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/workspace/assets/modules
    mkdir -p /home/user/workspace/src

    ln -s /home/user/workspace/assets /home/user/workspace/assets/modules/loop

    for i in $(seq 1 100); do
        touch /home/user/workspace/assets/file_$i.png
        touch /home/user/workspace/src/source_$i.c
    done

    cat << 'EOF' > /home/user/workspace/build.sh
#!/bin/bash
rm -f /home/user/workspace/manifest.txt
touch /home/user/workspace/manifest.txt

./process_assets.sh /home/user/workspace/assets &
./compile.sh /home/user/workspace/src &

wait
echo "Build complete."
EOF
    chmod +x /home/user/workspace/build.sh

    cat << 'EOF' > /home/user/workspace/process_assets.sh
#!/bin/bash
# process_assets.sh
shopt -s nullglob
process_dir() {
    local dir=$1
    for f in "$dir"/*; do
        if [ -d "$f" ]; then
            process_dir "$f"
        elif [ -f "$f" ]; then
            # Register file
            contents=$(cat /home/user/workspace/manifest.txt)
            echo -e "${contents}\n$f" > /home/user/workspace/manifest.txt
        fi
    done
}
process_dir "$1"
EOF
    chmod +x /home/user/workspace/process_assets.sh

    cat << 'EOF' > /home/user/workspace/compile.sh
#!/bin/bash
# compile.sh
shopt -s nullglob
for f in "$1"/*; do
    if [ -f "$f" ]; then
        # Register compiled file
        contents=$(cat /home/user/workspace/manifest.txt)
        echo -e "${contents}\n$f.o" > /home/user/workspace/manifest.txt
    fi
done
EOF
    chmod +x /home/user/workspace/compile.sh

    cat << 'EOF' > /home/user/workspace/build_error.log
process_assets.sh: line 8: process_dir: maximum recursion depth exceeded
Traceback (most recent call last):
  File "process_assets.sh", line 8, in process_dir
  File "process_assets.sh", line 8, in process_dir
...
EOF

    chmod -R 777 /home/user
