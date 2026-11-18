#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx redis-server gcc zlib1g-dev libhiredis-dev curl
    pip3 install pytest

    mkdir -p /app/nginx /app/backup_agent /app/configs /app/logs /app/scripts

    # Create symlink loop for the task
    ln -s /app/configs /app/configs/legacy

    # Create some dummy config files with 16-byte headers
    echo "1234567890123456config_data_1" > /app/configs/conf1.dat
    echo "1234567890123456config_data_2" > /app/configs/conf2.dat

    # Broken Nginx config
    cat << 'EOF' > /app/nginx/nginx.conf
events {
    worker_connections 1024;
}
http {
    access_log /app/logs/update.log;
    server {
        listen 8080;
        location /upload {
            # Broken logging configuration
            return 200 "Uploaded\n";
        }
    }
}
EOF

    # Broken Backup Agent C code
    cat << 'EOF' > /app/backup_agent/agent.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <dirent.h>
#include <unistd.h>
#include <zlib.h>
#include <hiredis/hiredis.h>

void process_dir(const char *path, gzFile out) {
    DIR *dir = opendir(path);
    if (!dir) return;
    struct dirent *entry;
    while ((entry = readdir(dir)) != NULL) {
        if (strcmp(entry->d_name, ".") == 0 || strcmp(entry->d_name, "..") == 0) continue;
        char full_path[1024];
        snprintf(full_path, sizeof(full_path), "%s/%s", path, entry->d_name);

        struct stat path_stat;
        // BUG: using stat instead of lstat, follows symlinks blindly
        if (stat(full_path, &path_stat) != 0) continue;

        if (S_ISDIR(path_stat.st_mode)) {
            process_dir(full_path, out);
        } else if (S_ISREG(path_stat.st_mode)) {
            FILE *f = fopen(full_path, "rb");
            if (f) {
                fseek(f, 16, SEEK_SET); // skip 16-byte header
                char buf[4096];
                size_t bytes;
                while ((bytes = fread(buf, 1, sizeof(buf), f)) > 0) {
                    gzwrite(out, buf, bytes);
                }
                fclose(f);
            }
        }
    }
    closedir(dir);
}

int main() {
    // In a real scenario, this reads from /app/logs/update.log
    // For now, we just process /app/configs directly for simplicity
    gzFile out = gzopen("/home/user/backup.gz", "wb");
    if (!out) return 1;
    process_dir("/app/configs", out);
    gzclose(out);
    return 0;
}
EOF

    # Init scripts
    cat << 'EOF' > /app/scripts/start_nginx.sh
#!/bin/bash
nginx -c /app/nginx/nginx.conf
EOF

    cat << 'EOF' > /app/scripts/start_redis.sh
#!/bin/bash
redis-server --daemonize yes
EOF

    chmod +x /app/scripts/*.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app /var/log/nginx /var/lib/nginx
