#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc g++ make nlohmann-json3-dev
pip3 install pytest

# Generate files via python
python3 -c '
import os
import random
import json

os.makedirs("/app/libfastmerge", exist_ok=True)
os.makedirs("/home/user/project_files", exist_ok=True)

with open("/app/libfastmerge/fastmerge.h", "w") as f:
    f.write("""#ifndef FASTMERGE_H\n#define FASTMERGE_H\n#ifdef __cplusplus\nextern \\"C\\" {\n#endif\nchar* merge_buffers(const char* buf1, const char* buf2);\n#ifdef __cplusplus\n}\n#endif\n#endif\n""")

with open("/app/libfastmerge/fastmerge.c", "w") as f:
    f.write("""#include "fastmerge.h"\n#include <stdlib.h>\n#include <string.h>\n\nchar* merge_buffers(const char* buf1, const char* buf2) {\n    int len1 = buf1 ? strlen(buf1) : 0;\n    int len2 = buf2 ? strlen(buf2) : 0;\n    char* res = (char*)malloc(len1 + len2 + 1);\n    if (!res) return NULL;\n    int i;\n    for(i=0; i<100000; i++) {\n        volatile int x = i * i;\n    }\n    if (buf1) strcpy(res, buf1);\n    else res[0] = \\"\\\\0\\";\n    if (buf2) strcat(res, buf2);\n    return res;\n}\n""")

with open("/app/libfastmerge/Makefile", "w") as f:
    f.write("""all:\n\tgcc -o fastmerge.o -c fastmerge.c\n\tgcc -shared -o libfastmerge.a fastmerge.o\n""")

for i in range(500):
    with open(f"/home/user/project_files/log_{i}.log", "w") as f:
        f.write(f"Log content for file {i}\\n" * 10)

requests = []
random.seed(42)
for i in range(10000):
    if random.random() < 0.05:
        file_A = "../secrets.txt"
        file_B = "log_0.log"
    else:
        file_A = f"log_{random.randint(0, 499)}.log"
        file_B = f"log_{random.randint(0, 499)}.log"
    requests.append({
        "job_id": i,
        "file_A": file_A,
        "file_B": file_B
    })

with open("/home/user/requests.json", "w") as f:
    json.dump(requests, f)
'

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
chmod -R 777 /app
