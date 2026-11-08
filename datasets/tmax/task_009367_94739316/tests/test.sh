#!/bin/bash
set +e
mkdir -p /logs/verifier /tmp/verifier-bin /tmp/verifier-ref
prep_status=0

cat > /tmp/rss_touch_audit.c <<'EOF'
#define _GNU_SOURCE
#include <stddef.h>
#include <fcntl.h>
#include <unistd.h>
#include <stdlib.h>

extern void *__libc_malloc(size_t);
extern void __libc_free(void *);

static void *large_ptrs[256];
static long large_allocs = 0;
static long large_frees = 0;

void *malloc(size_t n) {
    void *p = __libc_malloc(n);
    if (p && n >= 1024 * 1024) {
        volatile unsigned char *q = (volatile unsigned char *)p;
        for (size_t i = 0; i < n; i += 4096) q[i] = 0;
        q[n - 1] = 0;
        if (large_allocs < 256) large_ptrs[large_allocs] = p;
        large_allocs++;
    }
    return p;
}

void free(void *p) {
    for (int i = 0; i < 256; i++) {
        if (large_ptrs[i] == p) {
            large_ptrs[i] = 0;
            large_frees++;
            break;
        }
    }
    __libc_free(p);
}

__attribute__((destructor)) static void save_audit(void) {
    const char *path = getenv("ALLOC_AUDIT_PATH");
    if (!path) return;
    int fd = open(path, O_WRONLY | O_CREAT | O_TRUNC, 0666);
    if (fd >= 0) {
        long values[2] = {large_allocs, large_frees};
        (void)write(fd, values, sizeof(values));
        close(fd);
    }
}
EOF

gcc -shared -fPIC -O2 -o /tmp/rss_touch_audit.so /tmp/rss_touch_audit.c
if [ $? -ne 0 ]; then prep_status=1; fi

cat > /tmp/verifier-bin/gcc <<'EOF'
#!/bin/bash
{
    printf '%q ' "$@"
    printf '\n'
} >> /tmp/gcc_invocations.log
exec /usr/bin/gcc "$@"
EOF
chmod +x /tmp/verifier-bin/gcc
: > /tmp/gcc_invocations.log

rm -f /home/user/bin/worker_x86 /home/user/bin/worker_arm /home/user/memory_report.json
if [ "$prep_status" -eq 0 ]; then
    PATH="/tmp/verifier-bin:$PATH" LD_PRELOAD=/tmp/rss_touch_audit.so python3 /home/user/ci_pipeline.py
    if [ $? -ne 0 ]; then prep_status=1; fi
fi

/usr/bin/gcc -DARCH_X86 /home/user/src/worker.c -o /tmp/verifier-ref/worker_x86
if [ $? -ne 0 ]; then prep_status=1; fi
/usr/bin/gcc -DARCH_ARM /home/user/src/worker.c -o /tmp/verifier-ref/worker_arm
if [ $? -ne 0 ]; then prep_status=1; fi

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import shlex
import struct
import filecmp
import subprocess
import pytest

SCRIPT = "/home/user/ci_pipeline.py"
BIN_X86 = "/home/user/bin/worker_x86"
BIN_ARM = "/home/user/bin/worker_arm"
REPORT = "/home/user/memory_report.json"
PRELOAD = "/tmp/rss_touch_audit.so"


def test_ci_pipeline_script_exists():
    """Check that the ci_pipeline.py script exists."""
    assert os.path.isfile(SCRIPT), f"Expected script {SCRIPT} does not exist."


def test_binaries_built():
    """Check that both binaries were successfully built and are executable."""
    assert os.path.isfile(BIN_X86), f"Binary {BIN_X86} was not built."
    assert os.access(BIN_X86, os.X_OK), f"Binary {BIN_X86} is not executable."
    assert os.path.isfile(BIN_ARM), f"Binary {BIN_ARM} was not built."
    assert os.access(BIN_ARM, os.X_OK), f"Binary {BIN_ARM} is not executable."


def test_compilation_used_source_and_architecture_flags():
    """Require both requested GCC builds, or deterministic default-GCC equivalents."""
    commands = []
    if os.path.isfile("/tmp/gcc_invocations.log"):
        with open("/tmp/gcc_invocations.log") as f:
            for line in f:
                try:
                    commands.append(shlex.split(line))
                except ValueError:
                    pass

    def logged(macro, output):
        for args in commands:
            has_source = any(os.path.basename(arg) == "worker.c" for arg in args)
            has_macro = macro in args
            has_output = any(
                (arg == output) or (arg.startswith("-o") and arg[2:] == output)
                for arg in args
            )
            if has_source and has_macro and has_output:
                return True
        return False

    x86_ok = logged("-DARCH_X86", BIN_X86) or filecmp.cmp(
        BIN_X86, "/tmp/verifier-ref/worker_x86", shallow=False
    )
    arm_ok = logged("-DARCH_ARM", BIN_ARM) or filecmp.cmp(
        BIN_ARM, "/tmp/verifier-ref/worker_arm", shallow=False
    )
    assert x86_ok, "worker_x86 was not compiled from worker.c with -DARCH_X86."
    assert arm_ok, "worker_arm was not compiled from worker.c with -DARCH_ARM."


def run_profile(binary, audit_path):
    env = os.environ.copy()
    env["LD_PRELOAD"] = PRELOAD
    env["ALLOC_AUDIT_PATH"] = audit_path
    result = subprocess.run(
        ["/usr/bin/time", "-v", binary],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        env=env,
        timeout=30,
    )
    assert result.returncode == 0, f"{binary} failed when executed: {result.stderr}"
    rss = None
    for line in result.stderr.splitlines():
        if "Maximum resident set size (kbytes)" in line:
            rss = int(line.rsplit(":", 1)[1].strip())
            break
    assert rss is not None, f"Could not profile peak RSS for {binary}."
    assert os.path.isfile(audit_path), f"No allocation audit was produced by {binary}."
    with open(audit_path, "rb") as f:
        raw = f.read()
    assert len(raw) == 16, f"Invalid allocation audit from {binary}."
    allocs, frees = struct.unpack("ll", raw)
    return rss, allocs, frees


@pytest.fixture(scope="module")
def observed_profiles():
    return {
        "worker_x86": run_profile(BIN_X86, "/tmp/x86.alloc"),
        "worker_arm": run_profile(BIN_ARM, "/tmp/arm.alloc"),
    }


def test_binaries_execute_with_expected_conditional_behavior(observed_profiles):
    x86_rss, x86_allocs, x86_frees = observed_profiles["worker_x86"]
    arm_rss, arm_allocs, arm_frees = observed_profiles["worker_arm"]
    assert x86_allocs == 50 and x86_frees == 50, (
        f"worker_x86 did not perform the expected 50 allocations and frees: "
        f"allocations={x86_allocs}, frees={x86_frees}"
    )
    assert arm_allocs == 50 and arm_frees == 0, (
        f"worker_arm did not retain the expected 50 allocations: "
        f"allocations={arm_allocs}, frees={arm_frees}"
    )
    assert arm_rss > x86_rss + 30000, "Executing worker_arm did not show the expected RSS leak."


def test_memory_report_exists_and_valid():
    """Check that the memory report exists and is valid JSON."""
    assert os.path.isfile(REPORT), f"Memory report {REPORT} does not exist."
    with open(REPORT, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {REPORT} is not valid JSON.")
    assert isinstance(data, dict), "JSON report should be a dictionary."


def test_memory_report_contents():
    """Check that the memory report contains the correct keys and values."""
    if not os.path.isfile(REPORT):
        pytest.skip("Memory report does not exist.")
    with open(REPORT, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.skip("Memory report is not valid JSON.")

    expected_keys = {"worker_x86", "worker_arm", "leak_detected"}
    assert set(data.keys()) == expected_keys, f"JSON report keys do not match expected. Found: {list(data.keys())}"
    assert data["leak_detected"] == "worker_arm", "Incorrect leak_detected value. Expected 'worker_arm'."
    assert isinstance(data["worker_x86"], int), "worker_x86 value must be an integer."
    assert isinstance(data["worker_arm"], int), "worker_arm value must be an integer."
    assert data["worker_arm"] > 40000, f"worker_arm peak RSS too low ({data['worker_arm']} KB), expected > 40000 KB."
    assert data["worker_x86"] < 10000, f"worker_x86 peak RSS too high ({data['worker_x86']} KB), expected < 10000 KB."


def test_report_matches_executed_binaries(observed_profiles):
    with open(REPORT) as f:
        data = json.load(f)
    for name in ("worker_x86", "worker_arm"):
        measured = observed_profiles[name][0]
        reported = data[name]
        assert abs(reported - measured) <= 8192, (
            f"Reported RSS for {name} ({reported} KB) does not match an independent "
            f"execution ({measured} KB)."
        )
TEST_EOF

python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1
pytest_status=$?

if [ "$prep_status" -eq 0 ] && [ "$pytest_status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
