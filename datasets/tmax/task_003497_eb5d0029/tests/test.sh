#!/bin/bash
mkdir -p /logs/verifier

cat <<'TRACE_EOF' > /tmp/trace_rename.c
#define _GNU_SOURCE
#include <sys/ptrace.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <sys/user.h>
#include <sys/syscall.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static int read_string(pid_t pid, unsigned long addr, char *out, size_t cap) {
    size_t pos = 0;
    while (pos + sizeof(long) <= cap) {
        long word = ptrace(PTRACE_PEEKDATA, pid, (void *)(addr + pos), 0);
        if (word == -1) return -1;
        memcpy(out + pos, &word, sizeof(word));
        if (memchr(&word, 0, sizeof(word))) return 0;
        pos += sizeof(word);
    }
    out[cap - 1] = 0;
    return 0;
}

int main(int argc, char **argv) {
    if (argc < 4) return 125;
    const char *log_path = argv[1];
    pid_t child = fork();
    if (child < 0) return 125;
    if (child == 0) {
        if (ptrace(PTRACE_TRACEME, 0, 0, 0) < 0) _exit(125);
        raise(SIGSTOP);
        execv(argv[2], &argv[2]);
        _exit(127);
    }

    int status;
    if (waitpid(child, &status, 0) < 0 || !WIFSTOPPED(status)) return 125;
    ptrace(PTRACE_SETOPTIONS, child, 0, PTRACE_O_TRACESYSGOOD | PTRACE_O_EXITKILL);

    int entering = 1;
    int pending = 0;
    char oldpath[4096] = {0}, newpath[4096] = {0};
    ptrace(PTRACE_SYSCALL, child, 0, 0);

    for (;;) {
        if (waitpid(child, &status, 0) < 0) return 125;
        if (WIFEXITED(status)) return WEXITSTATUS(status);
        if (WIFSIGNALED(status)) return 128 + WTERMSIG(status);

        int sig = WSTOPSIG(status);
        if (sig == (SIGTRAP | 0x80)) {
            struct user_regs_struct regs;
            if (ptrace(PTRACE_GETREGS, child, 0, &regs) < 0) return 125;
            if (entering) {
                pending = 0;
                long nr = (long)regs.orig_rax;
                unsigned long oldaddr = 0, newaddr = 0;
#ifdef SYS_rename
                if (nr == SYS_rename) {
                    oldaddr = regs.rdi;
                    newaddr = regs.rsi;
                    pending = 1;
                }
#endif
#ifdef SYS_renameat
                if (nr == SYS_renameat) {
                    oldaddr = regs.rsi;
                    newaddr = regs.r10;
                    pending = 1;
                }
#endif
#ifdef SYS_renameat2
                if (nr == SYS_renameat2) {
                    oldaddr = regs.rsi;
                    newaddr = regs.r10;
                    pending = 1;
                }
#endif
                if (pending && (read_string(child, oldaddr, oldpath, sizeof(oldpath)) < 0 ||
                                read_string(child, newaddr, newpath, sizeof(newpath)) < 0)) {
                    pending = 0;
                }
            } else if (pending && (long)regs.rax == 0) {
                FILE *f = fopen(log_path, "a");
                if (f) {
                    fprintf(f, "%s\t%s\n", oldpath, newpath);
                    fclose(f);
                }
                pending = 0;
            }
            entering = !entering;
            ptrace(PTRACE_SYSCALL, child, 0, 0);
        } else {
            int deliver = (sig == SIGTRAP || sig == SIGSTOP) ? 0 : sig;
            ptrace(PTRACE_SYSCALL, child, 0, deliver);
        }
    }
}
TRACE_EOF

gcc -O2 -Wall -o /tmp/trace_rename /tmp/trace_rename.c >/tmp/trace_build.log 2>&1

cat <<'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import subprocess
import tempfile

EXECUTABLE = "/home/user/ingest"
SOURCE = "/home/user/ingest.cpp"
CLEAN_CORPUS = "/app/corpus/clean"
EVIL_CORPUS = "/app/corpus/evil"
TRACER = "/tmp/trace_rename"
TOKEN = "crimson typhoon"


def run(args, **kwargs):
    return subprocess.run(args, capture_output=True, timeout=10, **kwargs)


def expected_pretty(value):
    return json.dumps(value, ensure_ascii=False, indent=4, sort_keys=True)


def assert_normalized_output(path, expected):
    with open(path, "r", encoding="utf-8") as f:
        text = f.read()
    assert json.loads(text) == expected
    assert text.rstrip("\n") == expected_pretty(expected)


def test_executable_exists():
    assert os.path.isfile(EXECUTABLE), f"Executable not found at {EXECUTABLE}"
    assert os.access(EXECUTABLE, os.X_OK), f"File at {EXECUTABLE} is not executable"
    assert os.path.isfile(SOURCE), f"Source not found at {SOURCE}"
    assert os.path.getsize(SOURCE) > 0


def test_evil_corpus_rejected():
    assert os.path.isdir(EVIL_CORPUS), f"Evil corpus missing at {EVIL_CORPUS}"
    evil_files = [f for f in os.listdir(EVIL_CORPUS) if os.path.isfile(os.path.join(EVIL_CORPUS, f))]
    assert len(evil_files) > 0, "Evil corpus is empty"
    bypassed_files = []
    with tempfile.TemporaryDirectory() as tmpdir:
        for filename in evil_files:
            input_path = os.path.join(EVIL_CORPUS, filename)
            output_path = os.path.join(tmpdir, filename)
            result = run([EXECUTABLE, input_path, tmpdir])
            if result.returncode == 0 or os.path.exists(output_path):
                bypassed_files.append(filename)
    assert not bypassed_files, f"{len(bypassed_files)} of {len(evil_files)} evil files bypassed validation: {', '.join(bypassed_files)}"


def test_clean_corpus_accepted():
    assert os.path.isdir(CLEAN_CORPUS), f"Clean corpus missing at {CLEAN_CORPUS}"
    clean_files = [f for f in os.listdir(CLEAN_CORPUS) if os.path.isfile(os.path.join(CLEAN_CORPUS, f))]
    assert len(clean_files) > 0, "Clean corpus is empty"
    failed_files = []
    with tempfile.TemporaryDirectory() as tmpdir:
        for filename in clean_files:
            input_path = os.path.join(CLEAN_CORPUS, filename)
            output_path = os.path.join(tmpdir, filename)
            result = run([EXECUTABLE, input_path, tmpdir])
            if result.returncode != 0 or not os.path.exists(output_path):
                failed_files.append(filename)
                continue
            try:
                with open(output_path, "r", encoding="utf-8") as f:
                    json.load(f)
            except Exception:
                failed_files.append(filename)
    assert not failed_files, f"{len(failed_files)} of {len(clean_files)} clean files were incorrectly rejected or modified: {', '.join(failed_files)}"


def test_unseen_utf8_and_utf16_inputs_are_normalized():
    nonce = secrets.token_hex(12)
    value = {
        "target_path": f"/srv/config/{nonce}",
        "auth_token": TOKEN,
        "nested": {"enabled": True, "count": 7, "message": "snowman ☃ and rocket 🚀"},
        "items": [3, "x", None, False],
    }
    encodings = ["utf8", "utf16-bom", "utf16-no-bom"]
    with tempfile.TemporaryDirectory() as root:
        outdir = os.path.join(root, "out")
        os.mkdir(outdir)
        for encoding in encodings:
            filename = f"unseen_{encoding}_{secrets.token_hex(6)}.json"
            input_path = os.path.join(root, filename)
            raw = json.dumps(value, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
            if encoding == "utf16-bom":
                raw = b"\xff\xfe" + raw.decode("utf-8").encode("utf-16le")
            elif encoding == "utf16-no-bom":
                raw = raw.decode("utf-8").encode("utf-16le")
            with open(input_path, "wb") as f:
                f.write(raw)
            result = run([EXECUTABLE, input_path, outdir])
            output_path = os.path.join(outdir, filename)
            assert result.returncode == 0, result.stderr.decode(errors="replace")
            assert os.path.isfile(output_path)
            assert_normalized_output(output_path, value)
            os.unlink(output_path)


def test_unseen_invalid_inputs_rejected_without_output():
    nonce = secrets.token_hex(10)
    cases = [
        {"auth_token": "wrong " + nonce, "target_path": "/safe/path"},
        {"auth_token": TOKEN, "target_path": f"/safe/{nonce}../escape"},
        {"target_path": "/safe/path"},
        {"auth_token": TOKEN},
        {"auth_token": 123, "target_path": "/safe/path"},
        {"auth_token": TOKEN, "target_path": ["/safe/path"]},
        [TOKEN, "/safe/path"],
    ]
    with tempfile.TemporaryDirectory() as root:
        for value in cases:
            name = f"reject_{secrets.token_hex(7)}.json"
            input_path = os.path.join(root, name)
            outdir = os.path.join(root, "out_" + secrets.token_hex(5))
            os.mkdir(outdir)
            with open(input_path, "w", encoding="utf-8") as f:
                json.dump(value, f)
            result = run([EXECUTABLE, input_path, outdir])
            assert result.returncode != 0
            assert os.listdir(outdir) == []

        malformed = os.path.join(root, f"malformed_{secrets.token_hex(7)}.json")
        outdir = os.path.join(root, "out_malformed")
        os.mkdir(outdir)
        with open(malformed, "wb") as f:
            f.write(b'\xff\xfe{\x00"\x00a\x00u\x00t\x00h\x00_\x00t\x00o\x00k\x00e\x00n\x00"\x00')
        result = run([EXECUTABLE, malformed, outdir])
        assert result.returncode != 0
        assert os.listdir(outdir) == []

        missing = os.path.join(root, "missing_" + secrets.token_hex(8) + ".json")
        outdir = os.path.join(root, "out_missing")
        os.mkdir(outdir)
        result = run([EXECUTABLE, missing, outdir])
        assert result.returncode != 0
        assert os.listdir(outdir) == []


def test_cli_requires_exactly_two_arguments():
    with tempfile.TemporaryDirectory() as root:
        input_path = os.path.join(root, "valid_" + secrets.token_hex(5) + ".json")
        outdir = os.path.join(root, "out")
        os.mkdir(outdir)
        with open(input_path, "w", encoding="utf-8") as f:
            json.dump({"auth_token": TOKEN, "target_path": "/safe/path"}, f)
        assert run([EXECUTABLE]).returncode != 0
        assert run([EXECUTABLE, input_path]).returncode != 0
        assert run([EXECUTABLE, input_path, outdir, "extra"]).returncode != 0
        assert os.listdir(outdir) == []


def test_successful_storage_uses_rename_in_output_directory():
    assert os.path.isfile(TRACER) and os.access(TRACER, os.X_OK), "rename syscall tracer failed to build"
    nonce = secrets.token_hex(16)
    value = {
        "auth_token": TOKEN,
        "target_path": f"/atomic/{nonce}",
        "payload": "z" * 200000,
    }
    with tempfile.TemporaryDirectory() as root:
        outdir = os.path.join(root, "destination")
        os.mkdir(outdir)
        filename = f"atomic_{secrets.token_hex(8)}.json"
        input_path = os.path.join(root, filename)
        output_path = os.path.join(outdir, filename)
        trace_path = os.path.join(root, "rename.log")
        with open(input_path, "w", encoding="utf-8") as f:
            json.dump(value, f)

        result = run([TRACER, trace_path, EXECUTABLE, input_path, outdir])
        assert result.returncode == 0, result.stderr.decode(errors="replace")
        assert os.path.isfile(output_path)
        assert_normalized_output(output_path, value)
        assert sorted(os.listdir(outdir)) == [filename], "temporary files were not cleaned up"
        assert os.path.isfile(trace_path), "no successful rename syscall was observed"

        matching = False
        with open(trace_path, "r", encoding="utf-8", errors="replace") as f:
            for line in f:
                parts = line.rstrip("\n").split("\t", 1)
                if len(parts) != 2:
                    continue
                src, dst = map(os.path.abspath, parts)
                if dst == os.path.abspath(output_path) and src != dst and os.path.dirname(src) == os.path.abspath(outdir):
                    matching = True
        assert matching, "final output was not atomically renamed from a temporary file in the output directory"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
