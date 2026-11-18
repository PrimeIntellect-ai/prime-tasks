#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc make
pip3 install pytest

useradd -m -s /bin/bash user || true

mkdir -p /home/user/project/src
mkdir -p /home/user/project/bin

cat << 'EOF' > /home/user/project/deps.json
{
  "main": ["math_ops", "string_ops"],
  "math_ops": ["advanced_math"],
  "string_ops": [],
  "advanced_math": []
}
EOF

cat << 'EOF' > /home/user/project/src/main.c
#include <stdio.h>

extern int math_op(int a, int b);
extern void string_op();

int main() {
#ifdef ARM_MODE
    printf("Running in ARM mode\n");
#else
    printf("Running in x86 mode\n");
#endif
    printf("Result: %d\n", math_op(2, 3));
    string_op();
    return 0;
}
EOF

cat << 'EOF' > /home/user/project/src/math_ops.c
extern int advanced_math_op(int base, int exp);

int math_op(int a, int b) {
    return advanced_math_op(a, b);
}
EOF

cat << 'EOF' > /home/user/project/src/advanced_math.c
#include <math.h>

int advanced_math_op(int base, int exp) {
    return (int)pow((double)base, (double)exp);
}
EOF

cat << 'EOF' > /home/user/project/src/string_ops.c
#include <stdio.h>

void string_op() {
    printf("String ops loaded.\n");
}
EOF

cat << 'EOF' > /home/user/project/build_system.py
import json
import os
import sys

def get_all_dependencies(graph, root):
    # BUG: Only gets immediate dependencies
    deps = set([root])
    if root in graph:
        for d in graph[root]:
            deps.add(d)
    return list(deps)

def generate_makefile():
    with open('deps.json', 'r') as f:
        graph = json.load(f)

    modules = get_all_dependencies(graph, 'main')

    print "Generating Makefile for modules:"
    for m in modules:
        print " -", m

    cflags = "-Wall"
    # The agent needs to add cross-compilation check here

    ldflags = ""
    # The agent needs to add -lm check here

    makefile_content = "CFLAGS = {cflags}\n".format(cflags=cflags)
    makefile_content += "LDFLAGS = {ldflags}\n\n".format(ldflags=ldflags)

    makefile_content += "all: bin/app\n\n"

    objs = ["src/{}.o".format(m) for m in modules]
    makefile_content += "bin/app: {}\n".format(" ".join(objs))
    makefile_content += "\t@mkdir -p bin\n"
    makefile_content += "\tgcc -o $@ $^ $(LDFLAGS)\n\n"

    for m in modules:
        makefile_content += "src/{m}.o: src/{m}.c\n".format(m=m)
        makefile_content += "\tgcc $(CFLAGS) -c $< -o $@\n\n"

    with open('Makefile', 'w') as f:
        f.write(makefile_content)

if __name__ == "__main__":
    generate_makefile()
EOF

chown -R user:user /home/user/project
chmod -R 777 /home/user
