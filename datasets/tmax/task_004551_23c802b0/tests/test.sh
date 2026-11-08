#!/bin/bash
set -e
mkdir -p /logs/verifier

WORK=/tmp/verifier_instrumentation
rm -rf "$WORK"
mkdir -p "$WORK"

PROCESSOR=/app/k8s-manifest-processor
if [ ! -f "$PROCESSOR" ] || [ ! -x "$PROCESSOR" ]; then
    echo "0" > /logs/verifier/reward.txt
    exit 0
fi
if [ "$(head -c 4 "$PROCESSOR" | od -An -tx1 | tr -d ' \n')" != "7f454c46" ]; then
    echo "0" > /logs/verifier/reward.txt
    exit 0
fi

restore_tools() {
    set +e
    if [ -e "$WORK/processor.real" ]; then
        rm -f "$PROCESSOR"
        mv "$WORK/processor.real" "$PROCESSOR"
    fi
    for name in expect xargs parallel iptables; do
        eval "path=\${WRAPPED_${name}_PATH:-}"
        if [ -n "$path" ] && [ -e "$WORK/${name}.real" ]; then
            rm -f "$path"
            mv "$WORK/${name}.real" "$path"
        fi
    done
}
trap restore_tools EXIT

install_tool_wrapper() {
    name="$1"
    path="$2"
    [ -e "$path" ] || return 0
    mv "$path" "$WORK/${name}.real"
    eval "WRAPPED_${name}_PATH=\"$path\""
    export "WRAPPED_${name}_PATH"
    cat > "$path" <<EOF
#!/bin/bash
printf '%q ' "\$@" >> "$WORK/${name}.log"
printf '\\n' >> "$WORK/${name}.log"
exec "$WORK/${name}.real" "\$@"
EOF
    chmod 755 "$path"
}

install_tool_wrapper expect /usr/bin/expect
install_tool_wrapper xargs /usr/bin/xargs
install_tool_wrapper parallel /usr/bin/parallel
install_tool_wrapper iptables /usr/sbin/iptables

mv "$PROCESSOR" "$WORK/processor.real"
printf '0 0\n' > "$WORK/concurrency"
: > "$WORK/processor_calls.log"
: > "$WORK/processor_stdin.log"
cat > "$PROCESSOR" <<EOF
#!/bin/bash
printf '%s\\n' "\$\$" >> "$WORK/processor_calls.log"
exec 9>"$WORK/concurrency.lock"
flock 9
read current maximum < "$WORK/concurrency"
current=\$((current + 1))
if [ "\$current" -gt "\$maximum" ]; then maximum="\$current"; fi
printf '%s %s\\n' "\$current" "\$maximum" > "$WORK/concurrency"
flock -u 9
sleep 0.05
flock 9
read current maximum < "$WORK/concurrency"
current=\$((current - 1))
printf '%s %s\\n' "\$current" "\$maximum" > "$WORK/concurrency"
flock -u 9
set -o pipefail
/usr/bin/tee -a "$WORK/processor_stdin.log" | "$WORK/processor.real"
exit \$?
EOF
chmod 755 "$PROCESSOR"

rm -rf /home/user/manifests/raw
mkdir -p /home/user/manifests/raw
python3 - <<'PY'
import os, secrets
raw = "/home/user/manifests/raw"
for i in range(1, 501):
    nonce = secrets.token_hex(16)
    data = (
        "apiVersion: v1\n"
        "kind: ConfigMap\n"
        "metadata:\n"
        f"  name: verifier-cm-{i}\n"
        "data:\n"
        f"  verifier_nonce: {nonce}\n"
        f"  index: \"{i}\"\n"
    )
    with open(os.path.join(raw, f"cm-{i}.yaml"), "w", encoding="utf-8") as f:
        f.write(data)
PY

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import os
import subprocess
import time

RAW = "/home/user/manifests/raw"
WORK = "/tmp/verifier_instrumentation"


def test_process_all_performance():
    script_path = "/home/user/process_all.sh"
    assert os.path.exists(script_path), f"Script {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable."
    assert os.path.exists(RAW), f"Directory {RAW} does not exist."

    source_paths = [os.path.join(RAW, f"cm-{i}.yaml") for i in range(1, 501)]
    original = {p: open(p, "rb").read() for p in source_paths}

    start = time.time()
    try:
        proc = subprocess.run(
            ["/bin/bash", script_path], capture_output=True, text=True, timeout=12
        )
    except subprocess.TimeoutExpired as exc:
        raise AssertionError("Script did not finish within the performance limit") from exc
    execution_time = time.time() - start

    optimized_files = glob.glob(os.path.join(RAW, "*.opt.yaml"))
    assert proc.returncode == 0, (
        f"Script failed to execute with return code {proc.returncode}.\n"
        f"stdout: {proc.stdout}\nstderr: {proc.stderr}"
    )
    assert len(optimized_files) >= 500, (
        f"Did not process 500 manifests. Found {len(optimized_files)} optimized files."
    )
    assert execution_time <= 10.0, (
        f"Execution time {execution_time:.2f} exceeds threshold of 10.0s."
    )

    for path, expected_source in original.items():
        assert os.path.isfile(path), f"Input manifest disappeared: {path}"
        assert open(path, "rb").read() == expected_source, f"Input manifest was replaced: {path}"
        output = path + ".opt.yaml"
        assert os.path.isfile(output), f"Missing processor output for {path}"
        expected_output = expected_source + b"\n# Processed\n"
        assert open(output, "rb").read() == expected_output, (
            f"Incorrect optimized output for {path}"
        )

    with open(os.path.join(WORK, "processor_calls.log"), encoding="utf-8") as f:
        calls = [line for line in f if line.strip()]
    assert len(calls) >= 500, "The manifest processor was not invoked for all 500 inputs."

    with open(os.path.join(WORK, "processor_stdin.log"), encoding="utf-8", errors="replace") as f:
        submitted = {line.strip() for line in f if line.strip()}
    missing = set(source_paths) - submitted
    assert not missing, f"Some manifests were not submitted to the processor: {sorted(missing)[:5]}"

    with open(os.path.join(WORK, "concurrency"), encoding="utf-8") as f:
        _, maximum = map(int, f.read().split())
    assert maximum >= 2, "Processor invocations were not run in parallel."

    expect_log = os.path.join(WORK, "expect.log")
    assert os.path.exists(expect_log) and os.path.getsize(expect_log) > 0, (
        "The script did not invoke expect for interactive automation."
    )

    parallel_used = any(
        os.path.exists(os.path.join(WORK, name + ".log"))
        and os.path.getsize(os.path.join(WORK, name + ".log")) > 0
        for name in ("xargs", "parallel")
    )
    assert parallel_used, "The script did not use xargs or parallel."

    iptables_log = os.path.join(WORK, "iptables.log")
    assert os.path.exists(iptables_log), "The script did not invoke iptables."
    rules = open(iptables_log, encoding="utf-8", errors="replace").read().splitlines()
    redirect_rule = any(
        "10.254.254.10" in line
        and "8080" in line
        and "OUTPUT" in line
        and ("REDIRECT" in line or "DNAT" in line)
        and ("-A" in line or "-I" in line)
        for line in rules
    )
    assert redirect_rule, "No telemetry redirection rule for 10.254.254.10:8080 was applied."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
