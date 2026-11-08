#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip vsftpd redis-server inotify-tools gcc bash
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/app
    mkdir -p /home/user/ftp/uploads
    mkdir -p /home/user/tests/evil_corpus
    mkdir -p /home/user/tests/clean_corpus
    mkdir -p /var/run/vsftpd/empty

    # Create dummy files for corpuses
    echo "foo/../../bar" > /home/user/tests/evil_corpus/1.txt
    echo "src/main.c" > /home/user/tests/clean_corpus/1.txt

    # Create filter_paths.c
    cat << 'EOF' > /home/user/app/filter_paths.c
#include <stdio.h>
int main(int argc, char **argv) {
    printf("SAFE\n");
    return 0;
}
EOF
    gcc -o /home/user/app/filter_paths /home/user/app/filter_paths.c

    # Create watcher.sh
    cat << 'EOF' > /home/user/app/watcher.sh
#!/bin/bash
echo $$ > /home/user/app/watcher.pid
while true; do
    sleep 1
done
EOF
    chmod +x /home/user/app/watcher.sh

    # Create watcher.pid
    echo "12345" > /home/user/app/watcher.pid

    # Configure vsftpd
    cat << 'EOF' > /etc/vsftpd.conf
listen=YES
listen_port=2121
anonymous_enable=YES
local_enable=YES
write_enable=YES
anon_upload_enable=YES
anon_mkdir_write_enable=YES
dirmessage_enable=YES
use_localtime=YES
xferlog_enable=YES
connect_from_port_20=YES
secure_chroot_dir=/var/run/vsftpd/empty
pam_service_name=vsftpd
ssl_enable=NO
seccomp_sandbox=NO
EOF

    chmod -R 777 /home/user
    chmod -R 777 /home/user/ftp
