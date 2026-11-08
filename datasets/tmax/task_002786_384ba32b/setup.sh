#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        gcc \
        libjson-c-dev \
        libssl-dev

    pip3 install pytest

    mkdir -p /app

    cat << 'EOF' > /app/legacy.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <stdbool.h>
#include <dirent.h>
#include <sys/stat.h>
#include <openssl/sha.h>
#include <json-c/json.h>

#define MAX_FILES 10000
#define MAX_EXTS 20

char *ignore_exts[MAX_EXTS];
int num_ignore_exts = 0;
bool follow_symlinks = false;
int extract_header_bytes = 16;

typedef struct {
    char *rel_path;
    char *full_path;
} FileEntry;

FileEntry files[MAX_FILES];
int num_files = 0;

bool has_ignored_ext(const char *path) {
    size_t len = strlen(path);
    for (int i = 0; i < num_ignore_exts; i++) {
        size_t elen = strlen(ignore_exts[i]);
        if (len >= elen && strcmp(path + len - elen, ignore_exts[i]) == 0) {
            return true;
        }
    }
    return false;
}

void traverse(const char *path, const char *rel_path) {
    DIR *dir = opendir(path);
    if (!dir) return;

    struct dirent *ent;
    char next_path[4096];
    char next_rel[4096];

    while ((ent = readdir(dir)) != NULL) {
        if (strcmp(ent->d_name, ".") == 0 || strcmp(ent->d_name, "..") == 0) continue;

        snprintf(next_path, sizeof(next_path), "%s/%s", path, ent->d_name);
        if (rel_path[0] == '\0') {
            snprintf(next_rel, sizeof(next_rel), "%s", ent->d_name);
        } else {
            snprintf(next_rel, sizeof(next_rel), "%s/%s", rel_path, ent->d_name);
        }

        struct stat st;
        int res = follow_symlinks ? stat(next_path, &st) : lstat(next_path, &st);
        if (res != 0) continue;

        if (S_ISDIR(st.st_mode)) {
            traverse(next_path, next_rel);
        } else if (S_ISREG(st.st_mode)) {
            if (!has_ignored_ext(next_rel)) {
                files[num_files].rel_path = strdup(next_rel);
                files[num_files].full_path = strdup(next_path);
                num_files++;
            }
        }
    }
    closedir(dir);
}

int cmp_file(const void *a, const void *b) {
    return strcmp(((FileEntry*)a)->rel_path, ((FileEntry*)b)->rel_path);
}

int main(int argc, char **argv) {
    if (argc != 3) return 1;

    struct json_object *parsed_json = json_object_from_file(argv[1]);
    if (parsed_json) {
        struct json_object *exts, *f_sym, *ex_hdr;
        if (json_object_object_get_ex(parsed_json, "ignore_extensions", &exts)) {
            int n = json_object_array_length(exts);
            for (int i = 0; i < n && i < MAX_EXTS; i++) {
                ignore_exts[num_ignore_exts++] = strdup(json_object_get_string(json_object_array_get_idx(exts, i)));
            }
        }
        if (json_object_object_get_ex(parsed_json, "follow_symlinks", &f_sym)) {
            follow_symlinks = json_object_get_boolean(f_sym);
        }
        if (json_object_object_get_ex(parsed_json, "extract_header_bytes", &ex_hdr)) {
            extract_header_bytes = json_object_get_int(ex_hdr);
        }
    }

    traverse(argv[2], "");

    qsort(files, num_files, sizeof(FileEntry), cmp_file);

    fwrite("BKUP", 1, 4, stdout);
    uint32_t nf = num_files;
    fwrite(&nf, 4, 1, stdout);

    for (int i = 0; i < num_files; i++) {
        uint16_t len = strlen(files[i].rel_path);
        fwrite(&len, 2, 1, stdout);
        fwrite(files[i].rel_path, 1, len, stdout);

        struct stat st;
        stat(files[i].full_path, &st);
        uint64_t size = st.st_size;
        fwrite(&size, 8, 1, stdout);

        FILE *f = fopen(files[i].full_path, "rb");
        unsigned char hash[SHA256_DIGEST_LENGTH];
        SHA256_CTX sha256;
        SHA256_Init(&sha256);
        char buf[8192];
        int bytes;
        while ((bytes = fread(buf, 1, sizeof(buf), f)) > 0) {
            SHA256_Update(&sha256, buf, bytes);
        }
        SHA256_Final(hash, &sha256);
        fwrite(hash, 1, SHA256_DIGEST_LENGTH, stdout);

        fseek(f, 0, SEEK_SET);
        char *hdr = calloc(1, extract_header_bytes);
        if (hdr) {
            fread(hdr, 1, extract_header_bytes, f);
            fwrite(hdr, 1, extract_header_bytes, stdout);
            free(hdr);
        }
        fclose(f);
    }

    return 0;
}
EOF

    gcc -O2 -o /app/legacy_backup_tool /app/legacy.c -ljson-c -lssl -lcrypto
    strip /app/legacy_backup_tool
    rm /app/legacy.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
