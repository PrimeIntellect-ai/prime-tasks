#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc
pip3 install pytest protobuf grpcio-tools

mkdir -p /home/user/polyglot_test
cd /home/user/polyglot_test

# 1. Create data.proto
cat << 'EOF' > data.proto
syntax = "proto3";
message RecordList {
    repeated string payloads = 1;
}
EOF

# 2. Create sorter.c
cat << 'EOF' > sorter.c
#include <string.h>
#include <stdlib.h>

struct StringWithIndex {
    const char* str;
    int index;
};

int compare(const void* a, const void* b) {
    return strcmp(((struct StringWithIndex*)a)->str, ((struct StringWithIndex*)b)->str);
}

void get_sorted_indices(const char** strings, int count, int* out_indices) {
    struct StringWithIndex* arr = malloc(count * sizeof(struct StringWithIndex));
    for(int i=0; i<count; i++) {
        arr[i].str = strings[i];
        arr[i].index = i;
    }
    qsort(arr, count, sizeof(struct StringWithIndex), compare);
    for(int i=0; i<count; i++) {
        out_indices[i] = arr[i].index;
    }
    free(arr);
}
EOF

# 3. Create python script to generate input.bin
python3 -m grpc_tools.protoc -I. --python_out=. data.proto

cat << 'EOF' > create_input.py
import base64
import data_pb2

words = ["Zebra", "Apple", "Mango", "Banana", "Cherry", "Xylophone"]
msg = data_pb2.RecordList()
for w in words:
    b64 = base64.b64encode(w.encode('utf-8')).decode('utf-8')
    msg.payloads.append(b64)

with open("input.bin", "wb") as f:
    f.write(msg.SerializeToString())
EOF

python3 create_input.py
rm create_input.py data_pb2.py

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
