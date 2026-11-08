#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Create user
    useradd -m -s /bin/bash user || true

    # Setup directories
    mkdir -p /home/user/data_to_backup/docs
    mkdir -p /home/user/data_to_backup/loop_a
    mkdir -p /home/user/data_to_backup/loop_b

    # Create circular symlinks
    ln -s /home/user/data_to_backup/loop_b /home/user/data_to_backup/loop_a/to_b
    ln -s /home/user/data_to_backup/loop_a /home/user/data_to_backup/loop_b/to_a

    # Create a valid symlink to test exclusion
    ln -s /home/user/data_to_backup/docs /home/user/data_to_backup/docs_link

    # Create config.xml with IPs
    cat << 'EOF' > /home/user/data_to_backup/config.xml
<?xml version="1.0" encoding="UTF-8"?>
<configuration>
    <server>
        <ip>192.168.1.100</ip>
        <port>8080</port>
    </server>
    <database>
        <connection>jdbc:mysql://10.0.0.5:3306/db</connection>
    </database>
    <nodes>
        <node ip="172.16.0.1" active="true" />
        <node ip="172.16.0.2" active="false" />
    </nodes>
</configuration>
EOF

    # Create app.log with multi-line errors
    cat << 'EOF' > /home/user/data_to_backup/app.log
[2023-10-01 10:00:00] INFO - Application started normally
[2023-10-01 10:05:12] WARNING - Memory usage high
[2023-10-01 10:15:30] ERROR - NullPointerException in processing module
    at com.app.Module.process(Module.java:42)
    at com.app.Main.run(Main.java:18)
[2023-10-01 10:16:00] INFO - Retrying process
[2023-10-01 10:16:05] ERROR - Database connection failed
    at com.db.Connection.connect(Connection.java:99)
    at com.db.Pool.getConnection(Pool.java:25)
    at com.app.Main.run(Main.java:22)
    Caused by: TimeoutException
[2023-10-01 10:20:00] INFO - Shutting down
EOF

    # Create the broken python script
    cat << 'EOF' > /home/user/backup_generator.py
import os
import tarfile

def create_backup(source_dir, output_file):
    with tarfile.open(output_file, "w:gz") as tar:
        # BUG: followlinks=True causes infinite loop with circular symlinks
        for root, dirs, files in os.walk(source_dir, followlinks=True):
            for file in files:
                filepath = os.path.join(root, file)
                # Missing size check and symlink exclusion logic
                arcname = os.path.relpath(filepath, source_dir)
                tar.add(filepath, arcname=arcname)

if __name__ == "__main__":
    create_backup("/home/user/data_to_backup", "/home/user/backup.tar.gz")
EOF

    chmod +x /home/user/backup_generator.py

    # Set permissions
    chmod -R 777 /home/user
