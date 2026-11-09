#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc gdb valgrind make git
    pip3 install pytest

    export HOME=/home/user
    mkdir -p $HOME
    cd $HOME

    # 1. Create the Git repository
    mkdir -p $HOME/event_daemon
    cd $HOME/event_daemon
    git init
    git config user.name "Dev"
    git config user.email "dev@example.com"

    # Commit 1: Initial state (No leak)
    cat << 'EOF' > main.c
#include <stdio.h>
#include <stdlib.h>

struct EventPayload {
    int id;
};

void process_event() {
    struct EventPayload* p = malloc(sizeof(struct EventPayload));
    p->id = 1;
    free(p);
}

int main() {
    process_event();
    return 0;
}
EOF
    cat << 'EOF' > Makefile
test_cancel:
	gcc -g main.c -o test_bin
	./test_bin
EOF
    git add main.c Makefile
    git commit -m "Initial commit"

    # Commit 2: Unrelated change
    echo "// Added comment" >> main.c
    git commit -am "Add comment"

    # Commit 3: Introduce the leak
    cat << 'EOF' > main.c
#include <stdio.h>
#include <stdlib.h>

struct EventPayload {
    int id;
};

struct TaskContext {
    int context_id;
    char buffer[256];
};

void process_event() {
    struct EventPayload* p = malloc(sizeof(struct EventPayload));
    struct TaskContext* ctx = malloc(sizeof(struct TaskContext));
    p->id = 1;
    ctx->context_id = 100;

    // Leak introduced: ctx is not freed on cancellation path
    free(p);
}

int main() {
    process_event();
    return 0;
}
EOF
    git commit -am "Refactor event processing and add TaskContext"
    LEAK_COMMIT=$(git rev-parse HEAD)

    # Commit 4: Another unrelated change
    echo "// End of file" >> main.c
    git commit -am "Add EOF comment"

    # 2. Create the crashing binary and core dump
    cd $HOME
    cat << 'EOF' > crash.c
#include <stdio.h>

void trigger_oom_crash() {
    int *ptr = NULL;
    *ptr = 42; // Intentionally cause segfault
}

void process_loop() {
    trigger_oom_crash();
}

int main() {
    process_loop();
    return 0;
}
EOF

    gcc -g crash.c -o event_daemon_crash_bin

    # Generate core dump using gdb since ulimit/sysctl may not work in build environment
    gdb --batch -ex "run" -ex "generate-core-file crash.core" ./event_daemon_crash_bin || true
    if [ ! -f crash.core ]; then
        touch crash.core
    fi

    # Write the expected solution to a hidden file for verification
    cat << EOF > $HOME/.expected_solution.json
{
  "crashing_function": "trigger_oom_crash",
  "leaking_commit_hash": "$LEAK_COMMIT",
  "leaked_struct_name": "TaskContext"
}
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
