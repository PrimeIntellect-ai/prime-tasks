#!/bin/bash
set +e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess
import textwrap

ROOT = "/home/user/telemd"

EXPECTED_MAKEFILE = """CC=gcc
CFLAGS=-g -O0 -pthread -Wall

all: telemd

telemd: main.c queue.c worker.c
\t$(CC) $(CFLAGS) -o telemd main.c queue.c worker.c

clean:
\trm -f telemd
"""

EXPECTED_TEST_SCRIPT = """#!/bin/bash
./telemd > /dev/null 2>&1
if [ $? -eq 0 ]; then
    echo "Tests passed!"
    exit 0
else
    echo "Tests failed! Service crashed."
    exit 1
fi
"""


def run(cmd, **kwargs):
    return subprocess.run(cmd, capture_output=True, text=True, **kwargs)


def test_resolution_log_exists_and_correct():
    log_path = "/home/user/resolution.log"
    assert os.path.isfile(log_path), f"Log file {log_path} does not exist."
    with open(log_path, "r") as f:
        content = f.read().strip()
    assert "SYSTEM_RESTORED_SUCCESS" in content, (
        f"Log file {log_path} does not contain the required success message. Found: '{content}'"
    )
    assert content == "SYSTEM_RESTORED_SUCCESS", "resolution.log must contain the exact required text"


def test_protected_files_unchanged():
    with open(os.path.join(ROOT, "Makefile"), "r") as f:
        assert f.read() == EXPECTED_MAKEFILE, "The provided Makefile was modified"
    with open(os.path.join(ROOT, "test_telemd.sh"), "r") as f:
        assert f.read() == EXPECTED_TEST_SCRIPT, "The provided test_telemd.sh was modified"


def test_rebuild_and_compiled_binary_exists():
    result = run(["make", "clean"], cwd=ROOT, timeout=20)
    assert result.returncode == 0, result.stdout + result.stderr
    result = run(["make"], cwd=ROOT, timeout=30)
    assert result.returncode == 0, result.stdout + result.stderr

    binary_path = os.path.join(ROOT, "telemd")
    assert os.path.isfile(binary_path), (
        f"Compiled binary {binary_path} does not exist. Make sure you recompiled the service using 'make'."
    )
    assert os.access(binary_path, os.X_OK), f"Binary {binary_path} is not executable."
    with open(binary_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", "telemd is not a compiled ELF executable"


def test_queue_synchronization_and_cycle_safety():
    harness = r'''
#include <pthread.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/wait.h>
#include <unistd.h>
#include "queue.h"

static volatile int queue_lock_calls = 0;
static volatile int queue_unlock_calls = 0;
static __thread int queue_lock_depth = 0;

int __real_pthread_mutex_lock(pthread_mutex_t *m);
int __real_pthread_mutex_unlock(pthread_mutex_t *m);

int __wrap_pthread_mutex_lock(pthread_mutex_t *m) {
    int rc = __real_pthread_mutex_lock(m);
    if (rc == 0 && m == &queue_mutex) {
        __sync_fetch_and_add(&queue_lock_calls, 1);
        queue_lock_depth++;
    }
    return rc;
}

int __wrap_pthread_mutex_unlock(pthread_mutex_t *m) {
    if (m == &queue_mutex) {
        __sync_fetch_and_add(&queue_unlock_calls, 1);
        queue_lock_depth--;
    }
    return __real_pthread_mutex_unlock(m);
}

static void clear_queue(void) {
    Node *p = head;
    while (p != NULL) {
        Node *next = p->next;
        free(p);
        p = next;
    }
    head = NULL;
}

static void *producer(void *arg) {
    long tid = (long)arg;
    for (int i = 0; i < 300; i++)
        enqueue_event((int)(tid * 300 + i));
    return NULL;
}

int main(void) {
    /* Verify ordinary queue behavior and that enqueue actually uses the
       queue mutex, rather than merely shipping a binary which returns zero. */
    enqueue_event(11);
    enqueue_event(22);
    enqueue_event(33);
    if (!head || head->event_id != 11 || !head->next ||
        head->next->event_id != 22 || !head->next->next ||
        head->next->next->event_id != 33 || head->next->next->next != NULL)
        return 10;
    if (queue_lock_calls < 3 || queue_unlock_calls != queue_lock_calls || queue_lock_depth != 0)
        return 11;
    clear_queue();

    /* Exercise concurrent insertion and require every event exactly once in
       a finite, uncorrupted list. */
    enum { THREADS = 6, PER_THREAD = 300, TOTAL = THREADS * PER_THREAD };
    pthread_t threads[THREADS];
    for (long i = 0; i < THREADS; i++)
        if (pthread_create(&threads[i], NULL, producer, (void *)i) != 0)
            return 12;
    for (int i = 0; i < THREADS; i++)
        if (pthread_join(threads[i], NULL) != 0)
            return 13;

    unsigned char *seen = calloc(TOTAL, 1);
    if (!seen) return 14;
    int count = 0;
    for (Node *p = head; p != NULL; p = p->next) {
        if (++count > TOTAL) return 15; /* cycle or extra nodes */
        if (p->event_id < 0 || p->event_id >= TOTAL || seen[p->event_id])
            return 16;
        seen[p->event_id] = 1;
    }
    if (count != TOTAL) return 17;
    for (int i = 0; i < TOTAL; i++)
        if (!seen[i]) return 18;
    free(seen);
    clear_queue();

    /* A real cycle must be handled without stack overflow, crash, or hang. */
    Node a = {1, NULL}, b = {2, NULL}, c = {3, NULL};
    a.next = &b;
    b.next = &c;
    c.next = &b;
    pid_t pid = fork();
    if (pid < 0) return 19;
    if (pid == 0) {
        alarm(3);
        process_events_recursive(&a);
        _exit(0);
    }
    int status = 0;
    if (waitpid(pid, &status, 0) != pid) return 20;
    if (!WIFEXITED(status) || WEXITSTATUS(status) != 0) return 21;
    return 0;
}
'''
    harness_path = "/tmp/telemd_hidden_harness.c"
    binary_path = "/tmp/telemd_hidden_harness"
    with open(harness_path, "w") as f:
        f.write(textwrap.dedent(harness))

    result = run([
        "gcc", "-g", "-O0", "-pthread", "-Wall", "-I", ROOT,
        harness_path, os.path.join(ROOT, "queue.c"), os.path.join(ROOT, "worker.c"),
        "-Wl,--wrap=pthread_mutex_lock", "-Wl,--wrap=pthread_mutex_unlock",
        "-o", binary_path,
    ], timeout=30)
    assert result.returncode == 0, "Submitted queue/worker sources do not compile:\n" + result.stdout + result.stderr

    result = run([binary_path], timeout=15)
    assert result.returncode == 0, (
        f"Queue concurrency/cycle harness failed with code {result.returncode}. "
        f"Output: {result.stdout.strip()} {result.stderr.strip()}"
    )


def test_telemd_test_script_passes():
    script_path = os.path.join(ROOT, "test_telemd.sh")
    assert os.path.isfile(script_path), f"Test script {script_path} is missing."
    result = run([script_path], cwd=ROOT, timeout=20)
    assert result.returncode == 0, (
        f"Test script {script_path} failed with exit code {result.returncode}. "
        f"The service might still be crashing. Output: {result.stdout.strip()} {result.stderr.strip()}"
    )
TEST_EOF

python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1
status=$?
if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
exit 0
