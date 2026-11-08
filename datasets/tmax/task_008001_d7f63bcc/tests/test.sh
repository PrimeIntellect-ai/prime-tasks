#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import shlex
import shutil
import subprocess
import tempfile
import uuid

CACHES = {
    "cache_a": {"path": "/home/user/cache_a", "port": "8081"},
    "cache_b": {"path": "/home/user/cache_b", "port": "8082"},
    "cache_c": {"path": "/home/user/cache_c", "port": "8083"},
}
CONF = "/home/user/proxy_backend.conf"
SOURCE = "/home/user/deploy_proxy.c"
EXECUTABLE = "/home/user/deploy_proxy"
SCRIPT = "/home/user/optimize_storage.sh"


def get_dir_size(path):
    total_size = 0
    for dirpath, _, filenames in os.walk(path):
        for filename in filenames:
            fp = os.path.join(dirpath, filename)
            if not os.path.islink(fp):
                total_size += os.path.getsize(fp)
    return total_size


def expected_content(name):
    return f"backend best_cache {{ server 127.0.0.1:{CACHES[name]['port']}; }}\n"


def read_conf():
    assert os.path.isfile(CONF), f"Configuration file {CONF} does not exist."
    with open(CONF, "r") as handle:
        return handle.read()


def run_program(path, args):
    return subprocess.run(
        [path] + args,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
        check=False,
    )


def exercise_program(path):
    for name in CACHES:
        with open(CONF, "w") as handle:
            handle.write("obsolete configuration that must be overwritten\ntrailing garbage\n")

        result = run_program(path, [name])
        assert result.returncode == 0, (
            f"{path} failed for {name}: {result.stderr.decode(errors='replace')}"
        )
        assert read_conf() == expected_content(name)

        result = run_program(path, [name])
        assert result.returncode == 0, f"{path} was not idempotent for {name}."
        assert read_conf() == expected_content(name)

    assert run_program(path, []).returncode != 0, (
        f"{path} must reject invocation without its one required argument."
    )
    assert run_program(path, ["cache_a", "cache_b"]).returncode != 0, (
        f"{path} must reject invocation with more than one argument."
    )


def test_deploy_proxy_c_exists():
    path = SOURCE
    assert os.path.isfile(path), f"Expected C source file {path} does not exist."


def test_deploy_proxy_executable_exists():
    path = EXECUTABLE
    assert os.path.isfile(path), f"Expected executable {path} does not exist."
    assert os.access(path, os.X_OK), f"File {path} is not executable."
    with open(path, "rb") as handle:
        assert handle.read(4) == b"\x7fELF", f"{path} is not a compiled executable."


def test_optimize_storage_sh_exists():
    path = SCRIPT
    assert os.path.isfile(path), f"Expected bash script {path} does not exist."
    assert os.access(path, os.X_OK), f"File {path} is not executable."


def test_c_source_compiles_and_programs_map_and_overwrite():
    fd, compiled = tempfile.mkstemp(prefix="deploy_proxy_test_", dir="/tmp")
    os.close(fd)
    os.unlink(compiled)
    try:
        result = subprocess.run(
            ["gcc", SOURCE, "-o", compiled],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=20,
            check=False,
        )
        assert result.returncode == 0, (
            "deploy_proxy.c did not compile:\n" + result.stderr.decode(errors="replace")
        )
        exercise_program(compiled)
        exercise_program(EXECUTABLE)
    finally:
        if os.path.exists(compiled):
            os.remove(compiled)


def write_megabytes(path, count):
    block = b"x" * (1024 * 1024)
    with open(path, "wb") as handle:
        for _ in range(count):
            handle.write(block)


def test_optimize_script_selects_dynamic_smallest_and_invokes_program():
    token = uuid.uuid4().hex
    backup_root = f"/home/user/.cache_verifier_backup_{token}"
    real_executable = f"/home/user/.deploy_proxy_real_{token}"
    marker = f"/tmp/deploy_proxy_calls_{token}"
    moved = []
    executable_moved = False

    os.mkdir(backup_root)
    try:
        for name, info in CACHES.items():
            assert os.path.isdir(info["path"]), f"Missing cache directory {info['path']}"
            destination = os.path.join(backup_root, name)
            os.rename(info["path"], destination)
            moved.append((info["path"], destination))
            os.mkdir(info["path"])

        os.rename(EXECUTABLE, real_executable)
        executable_moved = True
        wrapper = (
            "#!/bin/bash\n"
            f"printf '%s\\n' \"$@\" >> {shlex.quote(marker)}\n"
            f"exec {shlex.quote(real_executable)} \"$@\"\n"
        )
        with open(EXECUTABLE, "w") as handle:
            handle.write(wrapper)
        os.chmod(EXECUTABLE, 0o755)

        scenarios = [
            {"cache_a": 1, "cache_b": 3, "cache_c": 5},
            {"cache_a": 5, "cache_b": 1, "cache_c": 3},
            {"cache_a": 3, "cache_b": 5, "cache_c": 1},
        ]

        for sizes in scenarios:
            for name, info in CACHES.items():
                for entry in os.listdir(info["path"]):
                    entry_path = os.path.join(info["path"], entry)
                    if os.path.isdir(entry_path) and not os.path.islink(entry_path):
                        shutil.rmtree(entry_path)
                    else:
                        os.remove(entry_path)
                write_megabytes(os.path.join(info["path"], "payload.bin"), sizes[name])

            smallest = min(sizes, key=sizes.get)
            if os.path.exists(marker):
                os.remove(marker)
            with open(CONF, "w") as handle:
                handle.write("stale data that must be replaced completely\n")

            result = subprocess.run(
                [SCRIPT],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=20,
                check=False,
            )
            assert result.returncode == 0, (
                f"optimize_storage.sh failed: {result.stderr.decode(errors='replace')}"
            )
            assert os.path.isfile(marker), (
                "optimize_storage.sh did not execute /home/user/deploy_proxy."
            )
            with open(marker, "r") as handle:
                calls = handle.read().splitlines()
            assert smallest in calls, (
                f"Expected deploy_proxy to be called with {smallest}, got {calls}."
            )
            assert read_conf() == expected_content(smallest)
    finally:
        if os.path.lexists(EXECUTABLE) and executable_moved:
            os.remove(EXECUTABLE)
        if executable_moved and os.path.exists(real_executable):
            os.rename(real_executable, EXECUTABLE)
        if os.path.exists(marker):
            os.remove(marker)
        for original, backup in reversed(moved):
            if os.path.lexists(original):
                if os.path.isdir(original) and not os.path.islink(original):
                    shutil.rmtree(original)
                else:
                    os.remove(original)
            if os.path.exists(backup):
                os.rename(backup, original)
        if os.path.isdir(backup_root):
            shutil.rmtree(backup_root)


def test_proxy_backend_conf_correctness():
    result = subprocess.run(
        [SCRIPT],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=20,
        check=False,
    )
    assert result.returncode == 0, (
        f"optimize_storage.sh failed on the current cache state: "
        f"{result.stderr.decode(errors='replace')}"
    )

    sizes = {}
    for name, info in CACHES.items():
        if os.path.isdir(info["path"]):
            try:
                output = subprocess.check_output(["du", "-sb", info["path"]]).decode("utf-8")
                size = int(output.split()[0])
            except Exception:
                size = get_dir_size(info["path"])
            sizes[name] = size
        else:
            sizes[name] = float("inf")

    smallest_cache = min(sizes, key=sizes.get)
    expected = expected_content(smallest_cache)
    assert os.path.isfile(CONF), f"Configuration file {CONF} does not exist. Did you run the script?"
    actual = read_conf()
    assert actual == expected, (
        f"Contents of {CONF} are incorrect.\n"
        f"Expected:\n{expected!r}\nActual:\n{actual!r}\n"
        f"Smallest cache was determined to be {smallest_cache}."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
