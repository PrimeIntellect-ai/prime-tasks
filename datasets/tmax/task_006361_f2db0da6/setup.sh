#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip g++ jq valgrind
pip3 install pytest

useradd -m -s /bin/bash user || true

cat << 'EOF' > /home/user/file_api.cpp
#include <iostream>
#include <dirent.h>
#include <sys/stat.h>
#include <string.h>
#include <stdlib.h>

void scan_dir(const char* path, std::string& json_out) {
    DIR *dir = opendir(path);
    if (!dir) return;

    struct dirent *entry;
    bool first = true;
    while ((entry = readdir(dir)) != NULL) {
        if (strcmp(entry->d_name, ".") == 0 || strcmp(entry->d_name, "..") == 0) continue;

        // BUG: Buffer overflow if path is long
        char* full_path = new char[100]; 
        strcpy(full_path, path);
        strcat(full_path, "/");
        strcat(full_path, entry->d_name);

        struct stat st;
        if (stat(full_path, &st) == 0) {
            if (!first) json_out += ",";
            first = false;

            if (S_ISDIR(st.st_mode)) {
                json_out += "{\"" + std::string(entry->d_name) + "\":[";
                scan_dir(full_path, json_out);
                json_out += "]}";
            } else {
                json_out += "{\"" + std::string(entry->d_name) + "\":" + std::to_string(st.st_size) + "}";
            }
        }
        // BUG: allocated with new[], freed with delete
        delete full_path; 
    }
    closedir(dir);
}

int main() {
    char* qs = getenv("QUERY_STRING");
    if (!qs || strncmp(qs, "dir=", 4) != 0) {
        std::cout << "Status: 400 Bad Request\r\n\r\n";
        return 1;
    }
    char* dir_path = qs + 4;

    std::string json_out = "[";
    scan_dir(dir_path, json_out);
    json_out += "]";

    std::cout << "Content-Type: application/json\r\n\r\n";
    std::cout << json_out << std::endl;

    return 0;
}
EOF

chmod -R 777 /home/user
