#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import collections
import ctypes
import errno
import os
import secrets
import shutil
import stat
import struct
import subprocess
import time

TOOL = "/app/txt2csv-tools-1.2/convert.sh"
SCRIPT = "/home/user/organize.sh"
RAW_DIR = "/home/user/raw_data"
PROCESSED_DIR = "/home/user/processed"
BY_DATE_DIR = "/home/user/by_date"


def expected_csv(dat_path):
    with open(dat_path, "r", encoding="utf-8") as f:
        lines = f.readlines()
    assert lines, f"Input file {dat_path} is empty."
    header = lines[0].split()
    assert len(header) >= 2, f"Malformed header in {dat_path}."
    output = [header[1] + "\n"]
    for line in lines[1:]:
        fields = line.split()
        assert len(fields) >= 2, f"Malformed data line in {dat_path}: {line!r}"
        output.append(fields[0] + "," + fields[1] + "\n")
    return "".join(output)


def test_tool_fixed():
    path = TOOL
    assert os.path.exists(path), f"Tool script {path} does not exist."
    with open(path, "r") as f:
        content = f.read()
    assert 'AWK_BIN="awk"' in content, f"The tool script {path} was not correctly fixed. Expected 'AWK_BIN=\"awk\"'."

    probe = f"/tmp/converter-probe-{secrets.token_hex(8)}.dat"
    probe_content = "DATE: 2041-07-19\n17 0.125\n88 9.75\n"
    with open(probe, "w", encoding="utf-8") as f:
        f.write(probe_content)
    try:
        result = subprocess.run([path, probe], text=True, capture_output=True, timeout=5)
        assert result.returncode == 0, f"The fixed converter failed on a probe input: {result.stderr}"
        assert result.stdout == "2041-07-19\n17,0.125\n88,9.75\n", "The fixed converter produced incorrect CSV output."
    finally:
        os.unlink(probe)


def test_script_exists_and_executable():
    path = SCRIPT
    assert os.path.isfile(path), f"Script {path} does not exist."
    st = os.stat(path)
    assert bool(st.st_mode & stat.S_IXUSR), f"Script {path} is not executable."


def test_execution_time_and_output():
    # Make one input unpredictable at verification time so static fabricated output
    # cannot satisfy the behavioral checks.
    challenge = os.path.join(RAW_DIR, "sensor_0.dat")
    day = secrets.randbelow(28) + 1
    challenge_lines = [f"DATE: 2042-11-{day:02d}\n"]
    for _ in range(5):
        challenge_lines.append(f"{secrets.randbelow(90) + 10} {secrets.randbelow(1000000) / 1000000:.6f}\n")
    with open(challenge, "w", encoding="utf-8") as f:
        f.writelines(challenge_lines)

    # Clear previous output directories to ensure a clean run.
    subprocess.run("rm -rf /home/user/processed/* /home/user/by_date/*", shell=True, check=True)

    # Wrap the submitted fixed converter during this run to verify that the
    # pipeline actually invokes it for every input.
    backup = "/tmp/convert.sh.verifier-original"
    call_log = "/tmp/convert-calls.log"
    try:
        os.unlink(call_log)
    except FileNotFoundError:
        pass
    shutil.copy2(TOOL, backup)
    original_mode = stat.S_IMODE(os.stat(TOOL).st_mode)
    wrapper = f'''#!/bin/bash
printf '%s\\t%s\\0' "$PWD" "$1" >> "{call_log}"
exec "{backup}" "$@"
'''
    with open(TOOL, "w", encoding="utf-8") as f:
        f.write(wrapper)
    os.chmod(TOOL, original_mode | stat.S_IXUSR)

    # Watch the processed directory. Atomic publication of a final .csv should
    # arrive as a rename (IN_MOVED_TO), not creation/opening of the final name.
    libc = ctypes.CDLL(None, use_errno=True)
    inotify_init1 = libc.inotify_init1
    inotify_init1.argtypes = [ctypes.c_int]
    inotify_init1.restype = ctypes.c_int
    inotify_add_watch = libc.inotify_add_watch
    inotify_add_watch.argtypes = [ctypes.c_int, ctypes.c_char_p, ctypes.c_uint32]
    inotify_add_watch.restype = ctypes.c_int
    IN_NONBLOCK = os.O_NONBLOCK
    IN_CREATE = 0x00000100
    IN_MOVED_TO = 0x00000080
    fd = inotify_init1(IN_NONBLOCK)
    assert fd >= 0, f"inotify_init1 failed: errno {ctypes.get_errno()}"
    wd = inotify_add_watch(fd, PROCESSED_DIR.encode(), IN_CREATE | IN_MOVED_TO)
    assert wd >= 0, f"inotify_add_watch failed: errno {ctypes.get_errno()}"
    non_atomic_csv_creates = []

    def drain_events():
        while True:
            try:
                data = os.read(fd, 65536)
            except BlockingIOError:
                return
            if not data:
                return
            offset = 0
            while offset < len(data):
                _, mask, _, name_len = struct.unpack_from("iIII", data, offset)
                offset += 16
                raw_name = data[offset:offset + name_len]
                offset += name_len
                name = raw_name.split(b"\0", 1)[0].decode("utf-8", "replace")
                if (mask & IN_CREATE) and name.endswith(".csv"):
                    non_atomic_csv_creates.append(name)

    cmd = f'/usr/bin/time -f "%e" {SCRIPT} > /tmp/time_out 2> /tmp/time_err'
    try:
        process = subprocess.Popen(cmd, shell=True, executable="/bin/bash")
        while process.poll() is None:
            drain_events()
            time.sleep(0.002)
        drain_events()
        returncode = process.returncode
    finally:
        os.close(fd)
        with open(TOOL, "wb") as f:
            with open(backup, "rb") as src:
                f.write(src.read())
        os.chmod(TOOL, original_mode)

    assert returncode == 0, "The organize.sh script failed to execute successfully."

    with open("/tmp/time_err", "r") as f:
        lines = f.read().strip().split('\n')
        time_str = lines[-1]
    try:
        exec_time = float(time_str)
    except ValueError:
        assert False, f"Could not parse execution time from time output: {time_str}"
    assert exec_time <= 10.0, f"Execution time {exec_time} exceeds the threshold of 10.0 seconds."

    assert not non_atomic_csv_creates, (
        "Final .csv paths were created directly instead of being atomically renamed into place: "
        + ", ".join(non_atomic_csv_creates[:10])
    )

    assert os.path.exists(call_log), "The pipeline did not invoke the fixed convert.sh tool."
    with open(call_log, "rb") as f:
        records = [r for r in f.read().split(b"\0") if r]
    invoked = collections.Counter()
    for record in records:
        cwd_raw, sep, arg_raw = record.partition(b"\t")
        assert sep, f"Malformed converter invocation record: {record!r}"
        cwd = os.fsdecode(cwd_raw)
        arg = os.fsdecode(arg_raw)
        invoked[os.path.realpath(arg if os.path.isabs(arg) else os.path.join(cwd, arg))] += 1

    inputs = {os.path.realpath(os.path.join(RAW_DIR, f)) for f in os.listdir(RAW_DIR) if f.endswith(".dat")}
    missing = sorted(path for path in inputs if invoked[path] == 0)
    assert not missing, f"organize.sh did not run convert.sh for every .dat input; missing: {missing[:10]}"


def test_processed_files():
    processed_dir = PROCESSED_DIR
    assert os.path.isdir(processed_dir), f"Directory {processed_dir} does not exist."

    files = [f for f in os.listdir(processed_dir) if f.endswith('.csv')]
    assert len(files) == 5000, f"Expected 5000 .csv files in {processed_dir}, found {len(files)}."

    dat_files = sorted(f for f in os.listdir(RAW_DIR) if f.endswith(".dat"))
    assert len(dat_files) == 5000, f"Expected 5000 .dat inputs, found {len(dat_files)}."
    expected_names = {os.path.splitext(f)[0] + ".csv" for f in dat_files}
    assert set(files) == expected_names, "Processed CSV filenames do not correspond exactly to the .dat inputs."

    for dat_name in dat_files:
        csv_name = os.path.splitext(dat_name)[0] + ".csv"
        dat_path = os.path.join(RAW_DIR, dat_name)
        csv_path = os.path.join(processed_dir, csv_name)
        assert os.path.isfile(csv_path) and not os.path.islink(csv_path), f"Expected a regular output file at {csv_path}."
        with open(csv_path, "r", encoding="utf-8") as f:
            actual = f.read()
        expected = expected_csv(dat_path)
        assert actual == expected, f"CSV content for {csv_name} does not match conversion of {dat_name}."


def test_symlinks_by_date():
    processed_dir = PROCESSED_DIR
    by_date_dir = BY_DATE_DIR

    processed_files = [f for f in os.listdir(processed_dir) if f.endswith('.csv')]
    assert len(processed_files) > 0, "No processed files found to check symlinks."

    for filename in processed_files:
        dat_path = os.path.join(RAW_DIR, os.path.splitext(filename)[0] + ".dat")
        expected_date = expected_csv(dat_path).splitlines()[0]
        csv_path = os.path.join(processed_dir, filename)

        symlink_path = os.path.join(by_date_dir, expected_date, filename)
        assert os.path.islink(symlink_path), f"Expected symlink at {symlink_path} does not exist."

        target = os.readlink(symlink_path)
        resolved_target = os.path.normpath(os.path.join(os.path.dirname(symlink_path), target))
        assert resolved_target == csv_path, f"Symlink {symlink_path} points to {resolved_target}, expected {csv_path}."


def test_atomic_writes_heuristic():
    script_path = SCRIPT
    with open(script_path, "r") as f:
        content = f.read()
    assert "mv " in content or "install " in content, "Script does not appear to use atomic writes (e.g., missing 'mv' command to move temporary files)."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
