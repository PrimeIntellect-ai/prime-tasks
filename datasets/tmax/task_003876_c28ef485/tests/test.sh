#!/bin/bash
set -u
mkdir -p /logs/verifier

cat << 'PY_EOF' > /tmp/test_final_state.py
import csv
import os
import re
import secrets
import shlex
import shutil
import signal
import subprocess
import tempfile

SCRIPT = "/home/user/run_etl.sh"
CSV_PATH = "/home/user/data/events.csv"
OUTPUT_DIR = "/home/user/output"

ALLOWED_COMMANDS = {
    ":", ".", "[", "[[", "((", "{", "}",
    "alias", "bg", "bind", "break", "builtin", "caller", "case", "cd",
    "command", "compgen", "complete", "continue", "declare", "dirs", "disown",
    "do", "done", "echo", "enable", "esac", "eval", "exec", "exit", "export",
    "false", "fc", "fg", "fi", "for", "function", "getopts", "hash", "help",
    "history", "if", "in", "jobs", "kill", "let", "local", "logout", "mapfile",
    "popd", "printf", "pushd", "pwd", "read", "readarray", "readonly", "return",
    "select", "set", "shift", "shopt", "source", "suspend", "test", "then",
    "times", "trap", "true", "type", "typeset", "ulimit", "umask", "unalias",
    "unset", "until", "wait", "while",
    "arch", "b2sum", "base32", "base64", "basename", "basenc", "cat", "chcon",
    "chgrp", "chmod", "chown", "cksum", "comm", "cp", "csplit", "cut", "date",
    "dd", "df", "dir", "dircolors", "dirname", "du", "env", "expand", "expr",
    "factor", "fmt", "fold", "groups", "head", "hostid", "id", "install", "join",
    "link", "ln", "logname", "ls", "md5sum", "mkdir", "mkfifo", "mknod",
    "mktemp", "mv", "nice", "nl", "nohup", "nproc", "numfmt", "od", "paste",
    "pathchk", "pinky", "pr", "printenv", "ptx", "readlink", "realpath", "rm",
    "rmdir", "runcon", "seq", "sha1sum", "sha224sum", "sha256sum", "sha384sum",
    "sha512sum", "shred", "shuf", "sleep", "sort", "split", "stat", "stdbuf",
    "stty", "sum", "sync", "tac", "tail", "tee", "timeout", "touch", "tr",
    "truncate", "tsort", "tty", "uname", "unexpand", "uniq", "unlink", "users",
    "vdir", "wc", "who", "whoami", "yes", "awk", "gawk", "mawk", "sed",
    "grep", "egrep", "fgrep", "find", "xargs"
}


def assert_script_is_valid():
    assert os.path.isfile(SCRIPT), f"Script {SCRIPT} does not exist."
    assert os.access(SCRIPT, os.X_OK), f"Script {SCRIPT} is not executable."

    with open(SCRIPT, "rb") as f:
        raw = f.read()
    assert b"\x00" not in raw, "run_etl.sh must be a text Bash script."
    source = raw.decode("utf-8")
    first_line = source.splitlines()[0] if source.splitlines() else ""
    assert first_line.startswith("#!") and re.search(r"(?:^|[/ ])bash(?:\s|$)", first_line), \
        "run_etl.sh must use Bash as its interpreter."

    syntax = subprocess.run(
        ["/bin/bash", "-n", SCRIPT], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True
    )
    assert syntax.returncode == 0, f"Invalid Bash syntax: {syntax.stderr}"
    return source


def make_fixture(path):
    rng = secrets.SystemRandom()
    regions = ["NA", "EU", "AP", "LATAM", "MEA", "R" + secrets.token_hex(3)]
    rows = []

    # Guarantee multiple sampled and unsampled successes and failures per region.
    next_id = rng.randrange(10000, 90000)
    for region in regions:
        for _ in range(6):
            rows.append([str(next_id), region, "SUCCESS", str(rng.randrange(1, 5000))])
            next_id += rng.randrange(1, 8)
        for _ in range(3):
            rows.append([str(next_id), region, "FAILED", str(rng.randrange(1, 5000))])
            next_id += rng.randrange(1, 8)

    for _ in range(350):
        status = "SUCCESS" if rng.randrange(100) < 63 else "FAILED"
        rows.append([
            str(next_id), rng.choice(regions), status, str(rng.randrange(1, 10000))
        ])
        next_id += rng.randrange(1, 10)
    rng.shuffle(rows)

    expected_sample = [["id", "region", "status", "amount"]]
    failed_count = 0
    success_sum = 0
    region_counts = {}
    for row in rows:
        if row[2] == "FAILED":
            failed_count += 1
        else:
            success_sum += int(row[3])
            region_counts[row[1]] = region_counts.get(row[1], 0) + 1
            if region_counts[row[1]] <= 3:
                expected_sample.append(row[:])

    with open(path, "w", newline="") as f:
        writer = csv.writer(f, lineterminator="\n")
        writer.writerow(["id", "region", "status", "amount"])
        writer.writerows(rows)
    os.chmod(path, 0o600)
    return expected_sample, failed_count, success_sum


def traced_commands(trace, source):
    function_names = set(re.findall(
        r"(?m)^\s*(?:function\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*(?:\(\s*\))?\s*\{",
        source
    ))
    commands = []
    for line in trace.splitlines():
        match = re.match(r"^\++\s+(.*)$", line)
        if not match:
            continue
        text = match.group(1).lstrip()
        if not text:
            continue
        try:
            parts = shlex.split(text, posix=True)
        except ValueError:
            parts = text.split()
        if not parts:
            continue
        index = 0
        while index < len(parts) and re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", parts[index]):
            index += 1
        if index >= len(parts):
            continue
        token = parts[index]
        if "=" in token and not token.startswith(("[", "(")):
            continue
        name = os.path.basename(token)
        if name in function_names:
            continue
        commands.append(name)
    return commands


def remove_output_dir():
    if os.path.islink(OUTPUT_DIR) or (os.path.lexists(OUTPUT_DIR) and not os.path.isdir(OUTPUT_DIR)):
        os.unlink(OUTPUT_DIR)
    elif os.path.isdir(OUTPUT_DIR):
        shutil.rmtree(OUTPUT_DIR)


def main():
    source = assert_script_is_valid()

    backup_fd, backup_path = tempfile.mkstemp(prefix="etl-original-", dir="/root")
    os.close(backup_fd)
    fixture_fd, fixture_path = tempfile.mkstemp(prefix="etl-fixture-", dir="/root")
    os.close(fixture_fd)
    shutil.copy2(CSV_PATH, backup_path)
    expected_sample, expected_failed, expected_sum = make_fixture(fixture_path)

    writer = None
    runner = None
    try:
        os.unlink(CSV_PATH)
        os.mkfifo(CSV_PATH, 0o666)
        os.chmod(CSV_PATH, 0o666)
        remove_output_dir()

        # A FIFO supplies the randomized CSV exactly once. Reopening the input
        # sequentially blocks, while concurrent readers split the byte stream.
        writer = subprocess.Popen(
            ["/bin/bash", "-c", 'exec /bin/cat "$1" > "$2"',
             "fifo-writer", fixture_path, CSV_PATH],
            stdout=subprocess.DEVNULL, stderr=subprocess.PIPE,
            start_new_session=True
        )
        runner = subprocess.Popen(
            ["/usr/bin/timeout", "12s", "/bin/bash", "-x", SCRIPT],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
            start_new_session=True,
            preexec_fn=lambda: os.setgid(1000) or os.setuid(1000)
        )
        try:
            stdout, trace = runner.communicate(timeout=15)
        except subprocess.TimeoutExpired:
            os.killpg(runner.pid, signal.SIGKILL)
            stdout, trace = runner.communicate()
            raise AssertionError("run_etl.sh did not finish from a single streaming input pass.")

        try:
            writer_rc = writer.wait(timeout=3)
        except subprocess.TimeoutExpired:
            os.killpg(writer.pid, signal.SIGKILL)
            writer.wait()
            raise AssertionError("run_etl.sh did not consume the complete input stream.")

        assert runner.returncode == 0, \
            f"run_etl.sh failed or timed out (exit {runner.returncode}). Trace:\n{trace}"
        assert writer_rc == 0, "run_etl.sh did not consume the complete input stream once."

        used = traced_commands(trace, source)
        disallowed = sorted(set(used) - ALLOWED_COMMANDS)
        assert not disallowed, \
            f"run_etl.sh used tools outside Bash built-ins/coreutils/awk/sed: {disallowed}"

        failed_path = os.path.join(OUTPUT_DIR, "failed_count.txt")
        sum_path = os.path.join(OUTPUT_DIR, "success_sum.txt")
        sample_path = os.path.join(OUTPUT_DIR, "sample.csv")

        assert os.path.isfile(failed_path), f"Output file {failed_path} does not exist."
        with open(failed_path) as f:
            actual_failed = f.read().strip()
        assert actual_failed == str(expected_failed), \
            f"Expected failed count {expected_failed}, got {actual_failed}."

        assert os.path.isfile(sum_path), f"Output file {sum_path} does not exist."
        with open(sum_path) as f:
            actual_sum = f.read().strip()
        assert actual_sum == str(expected_sum), \
            f"Expected success sum {expected_sum}, got {actual_sum}."

        assert os.path.isfile(sample_path), f"Output file {sample_path} does not exist."
        with open(sample_path, newline="") as f:
            actual_sample = list(csv.reader(f))
        assert actual_sample == expected_sample, \
            f"Expected sample CSV content {expected_sample}, got {actual_sample}."
    finally:
        if runner is not None and runner.poll() is None:
            os.killpg(runner.pid, signal.SIGKILL)
            runner.wait()
        if writer is not None and writer.poll() is None:
            os.killpg(writer.pid, signal.SIGKILL)
            writer.wait()
        if os.path.lexists(CSV_PATH):
            if os.path.isdir(CSV_PATH) and not os.path.islink(CSV_PATH):
                shutil.rmtree(CSV_PATH)
            else:
                os.unlink(CSV_PATH)
        os.makedirs(os.path.dirname(CSV_PATH), exist_ok=True)
        shutil.copy2(backup_path, CSV_PATH)
        os.chown(CSV_PATH, 1000, 1000)
        os.unlink(backup_path)
        os.unlink(fixture_path)


if __name__ == "__main__":
    main()
PY_EOF

if python3 /tmp/test_final_state.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
