#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    mkdir -p /home/user/project
    cd /home/user/project

    cat << 'EOF' > /home/user/project/init_db.sh
#!/bin/bash
rm -f /home/user/project/build_state.db
sqlite3 /home/user/project/build_state.db "CREATE TABLE tasks (id INTEGER PRIMARY KEY, module_name TEXT, status TEXT);"
for i in {1..15}; do
    sqlite3 /home/user/project/build_state.db "INSERT INTO tasks (module_name, status) VALUES ('mod_$i', 'pending');"
done
EOF
    chmod +x /home/user/project/init_db.sh

    cat << 'EOF' > /home/user/project/build.sh
#!/bin/bash
cd /home/user/project

modules=$(sqlite3 build_state.db "SELECT module_name FROM tasks WHERE status='pending';")

for mod in $modules; do
    (
        # Simulate compilation
        sleep 0.5
        # Update status
        sqlite3 build_state.db "UPDATE tasks SET status='done' WHERE module_name='$mod';"
    ) &
done

wait

pending=$(sqlite3 build_state.db "SELECT count(*) FROM tasks WHERE status='pending';")

if [ "$pending" -gt 0 ]; then
    echo "Build failed! $pending modules still pending."
    exit 1
else
    echo "Build successful."
    exit 0
fi
EOF
    chmod +x /home/user/project/build.sh

    /home/user/project/init_db.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
