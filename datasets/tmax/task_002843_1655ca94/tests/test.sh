#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import collections
import glob
import os
import stat
import subprocess
import time


def test_config_exists():
    config_path = "/etc/telemetry/settings.conf"
    assert os.path.exists(config_path), f"Config file {config_path} was not created to fix the segfault."
    assert os.path.isfile(config_path), f"Config path {config_path} is not a regular file."
    assert os.access(config_path, os.R_OK), f"Config file {config_path} is not readable."


def test_plugin_compiled():
    plugin_so = "/home/user/plugin/parser_plugin.so"
    assert os.path.exists(plugin_so), f"Compiled plugin {plugin_so} does not exist. Did you compile it correctly?"
    assert os.path.isfile(plugin_so), f"Plugin {plugin_so} is not a regular file."

    elf = subprocess.run(
        ["readelf", "-h", plugin_so], capture_output=True, text=True
    )
    assert elf.returncode == 0 and "DYN (Shared object file)" in elf.stdout, \
        f"{plugin_so} is not a valid ELF shared object: {elf.stderr}"

    # Load and call the required symbol in a child process so a malformed library
    # cannot crash the verifier itself.
    probe = subprocess.run(
        ["python3", "-c",
         "import ctypes; p=ctypes.CDLL('/home/user/plugin/parser_plugin.so'); "
         "f=p.process_data; f.argtypes=[ctypes.c_char_p]; f.restype=None; "
         "f(b'/tmp/plugin_probe.dat')"],
        capture_output=True, text=True, timeout=5
    )
    assert probe.returncode == 0, \
        f"Plugin cannot be loaded or its process_data symbol cannot be called: {probe.stderr}"


def test_parser_runs_with_repaired_environment():
    parser = "/app/telemetry_parser"
    assert os.path.isfile(parser), f"Parser {parser} is missing."
    assert os.access(parser, os.X_OK), f"Parser {parser} is not executable."
    with open(parser, "rb") as f:
        image = f.read()
    assert image.startswith(b"\x7fELF"), "The proprietary telemetry parser was replaced with a non-ELF file."
    for marker in (b"/etc/telemetry/settings.conf", b"PLUGIN_PATH", b"process_data"):
        assert marker in image, f"The telemetry parser does not contain expected functionality ({marker!r})."

    probe = "/tmp/verifier_parser_probe.dat"
    output = probe + ".processed"
    with open(probe, "w") as f:
        f.write("probe\n")
    try:
        if os.path.exists(output):
            os.remove(output)
        env = os.environ.copy()
        env["PLUGIN_PATH"] = "/home/user/plugin/parser_plugin.so"
        started = time.monotonic()
        result = subprocess.run(
            [parser, probe], env=env, capture_output=True, text=True, timeout=5
        )
        elapsed = time.monotonic() - started
        assert result.returncode == 0, \
            f"Parser still crashes or fails with the repaired config/plugin: {result.stderr}"
        assert elapsed >= 0.01, "The supplied telemetry parser appears to have been replaced by a no-op."
        assert os.path.isfile(output), "Parser did not create its processed output."
        with open(output) as f:
            assert f.read() == "OK\n", "Parser produced an invalid processed output."
    finally:
        for path in (probe, output):
            try:
                os.remove(path)
            except FileNotFoundError:
                pass


def test_wrapper_script_exists_and_executable():
    script_path = "/home/user/run_diagnostics.sh"
    assert os.path.exists(script_path), f"Wrapper script {script_path} not found."
    st = os.stat(script_path)
    assert bool(st.st_mode & stat.S_IXUSR), f"Wrapper script {script_path} is not executable."


def test_wrapper_script_performance_and_correctness():
    script_path = "/home/user/run_diagnostics.sh"
    target_dir = "/app/data"
    parser = "/app/telemetry_parser"
    real_parser = "/tmp/verifier_telemetry_parser.real"
    proxy_source = "/tmp/verifier_parser_proxy.c"
    invocation_log = "/tmp/verifier_parser_invocations.log"

    expected_inputs = sorted(os.path.realpath(p) for p in glob.glob(f"{target_dir}/*.dat"))
    assert len(expected_inputs) == 1000, "Test data set does not contain the expected 1000 .dat files."

    # Clear any previous runs to ensure we measure the actual script execution.
    for f in glob.glob(f"{target_dir}/*.processed"):
        os.remove(f)
    try:
        os.remove(invocation_log)
    except FileNotFoundError:
        pass

    proxy_code = r'''
#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

static long long now_ns(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (long long)ts.tv_sec * 1000000000LL + ts.tv_nsec;
}

static void record(char phase, const char *plugin, const char *arg) {
    int fd = open("/tmp/verifier_parser_invocations.log", O_WRONLY|O_CREAT|O_APPEND, 0600);
    if (fd >= 0) {
        dprintf(fd, "%c\t%d\t%lld\t%s\t%s\n", phase, (int)getpid(), now_ns(),
                plugin ? plugin : "", arg ? arg : "");
        close(fd);
    }
}

int main(int argc, char **argv) {
    const char *plugin = getenv("PLUGIN_PATH");
    const char *arg = argc > 1 ? argv[1] : "";
    record('S', plugin, arg);
    pid_t child = fork();
    if (child == 0) {
        execv("/tmp/verifier_telemetry_parser.real", argv);
        _exit(127);
    }
    if (child < 0) return 126;
    int status = 0;
    while (waitpid(child, &status, 0) < 0 && errno == EINTR) {}
    record('E', plugin, arg);
    if (WIFEXITED(status)) return WEXITSTATUS(status);
    if (WIFSIGNALED(status)) return 128 + WTERMSIG(status);
    return 125;
}
'''

    with open(proxy_source, "w") as f:
        f.write(proxy_code)

    os.replace(parser, real_parser)
    try:
        built = subprocess.run(
            ["gcc", "-O2", proxy_source, "-o", parser],
            capture_output=True, text=True
        )
        assert built.returncode == 0, f"Could not build parser invocation monitor: {built.stderr}"
        os.chmod(parser, 0o755)

        start_time = time.time()
        result = subprocess.run(
            [script_path, target_dir], capture_output=True, text=True, timeout=8
        )
        elapsed = time.time() - start_time
    finally:
        try:
            os.remove(parser)
        except FileNotFoundError:
            pass
        os.replace(real_parser, parser)

    assert result.returncode == 0, \
        f"Wrapper exited with status {result.returncode}: {result.stderr}\n{result.stdout}"

    processed_files = glob.glob(f"{target_dir}/*.processed")
    assert len(processed_files) == 1000, \
        f"Error: Only {len(processed_files)}/1000 files were processed. Script output: {result.stderr}\n{result.stdout}"
    for source in expected_inputs:
        output = source + ".processed"
        assert os.path.isfile(output), f"Missing parser output for {source}."
        with open(output) as f:
            assert f.read() == "OK\n", f"Invalid parser output for {source}."

    assert elapsed <= 5.0, \
        f"Performance requirement failed. Execution time was {elapsed:.2f} seconds, which is > 5.0 seconds threshold. Ensure you are processing files concurrently."

    assert os.path.isfile(invocation_log), "The wrapper never invoked /app/telemetry_parser."
    starts = []
    ends = {}
    intervals = {}
    with open(invocation_log) as f:
        for line in f:
            fields = line.rstrip("\n").split("\t", 4)
            assert len(fields) == 5, f"Malformed parser invocation record: {line!r}"
            phase, pid_text, timestamp_text, plugin, arg = fields
            pid = int(pid_text)
            timestamp = int(timestamp_text)
            assert plugin == "/home/user/plugin/parser_plugin.so", \
                f"Parser was invoked without the required PLUGIN_PATH for {arg}."
            canonical_arg = os.path.realpath(arg)
            if phase == "S":
                starts.append(canonical_arg)
                intervals[pid] = [timestamp, None]
            elif phase == "E":
                ends[pid] = canonical_arg
                assert pid in intervals, "Parser completion was logged without a start."
                intervals[pid][1] = timestamp
            else:
                assert False, f"Unknown invocation phase {phase!r}."

    assert collections.Counter(starts) == collections.Counter(expected_inputs), \
        "The wrapper must invoke /app/telemetry_parser exactly once for every .dat file."
    assert len(intervals) == 1000 and len(ends) == 1000, \
        "Not all telemetry parser invocations completed."
    assert all(end is not None and end >= begin for begin, end in intervals.values()), \
        "Invalid parser execution intervals were recorded."

    events = []
    for begin, end in intervals.values():
        events.append((begin, 0, 1))
        events.append((end, 1, -1))
    active = peak = 0
    for _, _, delta in sorted(events):
        active += delta
        peak = max(peak, active)
    assert peak >= 2, "No overlapping parser executions were observed; processing was sequential."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
