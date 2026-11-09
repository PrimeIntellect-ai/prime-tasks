#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import shutil
import socket
import stat
import subprocess
import tempfile
import uuid

import pytest

HOME = "/home/user"
AUDIT = f"{HOME}/audit_script.sh"
WRAPPER = f"{HOME}/run_sandbox.sh"


def run(cmd, timeout=30):
    return subprocess.run(cmd, text=True, stdout=subprocess.PIPE,
                          stderr=subprocess.PIPE, timeout=timeout)


@pytest.fixture(scope="session", autouse=True)
def execute_submitted_wrapper():
    for path in (AUDIT, WRAPPER):
        assert os.path.isfile(path), f"File {path} does not exist or is not a regular file."
        assert not os.path.islink(path), f"{path} must be a regular script, not a symlink."
        assert os.access(path, os.X_OK), f"{path} is not executable."

    result = run([WRAPPER], timeout=30)
    assert result.returncode == 0, (
        f"run_sandbox.sh failed with status {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def test_breached_ips_content():
    breached_ips_path = "/home/user/breached_ips.txt"
    assert os.path.isfile(breached_ips_path), f"File {breached_ips_path} does not exist."

    with open(breached_ips_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_ips = ["172.16.0.4", "192.168.1.10"]
    assert sorted(lines) == expected_ips, f"Expected {expected_ips} in {breached_ips_path}, but got {lines}."


def test_vulnerable_binaries_content():
    vuln_binaries_path = "/home/user/vulnerable_binaries.txt"
    assert os.path.isfile(vuln_binaries_path), f"File {vuln_binaries_path} does not exist."

    with open(vuln_binaries_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_binaries = ["vuln_echo"]
    assert sorted(lines) == expected_binaries, f"Expected {expected_binaries} in {vuln_binaries_path}, but got {lines}."


def test_run_sandbox_script():
    sandbox_script_path = "/home/user/run_sandbox.sh"
    assert os.path.isfile(sandbox_script_path), f"File {sandbox_script_path} does not exist."

    with open(sandbox_script_path, "r") as f:
        content = f.read()

    assert "bwrap" in content, "The run_sandbox.sh script does not invoke 'bwrap'."

    required_flags = [
        "--unshare-net",
        "--ro-bind /usr /usr",
        "--ro-bind /bin /bin",
        "--ro-bind /lib /lib",
        "--ro-bind /lib64 /lib64",
        "--rw-bind /home/user /home/user",
        "--dev /dev"
    ]

    normalized_content = " ".join(content.split())
    for flag in required_flags:
        normalized_flag = " ".join(flag.split())
        assert normalized_flag in normalized_content, (
            f"Missing required bwrap flag/mount: '{flag}' in {sandbox_script_path}"
        )


def test_audit_script_on_generated_inputs():
    suffix = uuid.uuid4().hex[:10]
    work = tempfile.mkdtemp(prefix=f"audit-{suffix}-", dir=HOME)
    auth = os.path.join(work, "generated-auth.log")
    binaries = os.path.join(work, "generated-binaries")
    os.mkdir(binaries)

    ip_good1 = f"10.31.{int(suffix[:2], 16)}.11"
    ip_good2 = f"10.32.{int(suffix[2:4], 16)}.12"
    ip_short = f"10.33.{int(suffix[4:6], 16)}.13"
    ip_early = f"10.34.{int(suffix[6:8], 16)}.14"
    ip_mixed = f"10.35.{int(suffix[8:10], 16)}.15"

    lines = [
        f"Feb 20 12:00:01 host sshd[1]: Failed password for alice from {ip_good1} port 22 ssh2",
        f"Feb 20 12:00:02 host sshd[2]: Failed password for alice from {ip_good1} port 22 ssh2",
        f"Feb 20 12:00:03 host sshd[3]: Failed password for alice from {ip_good1} port 22 ssh2",
        f"Feb 20 12:00:04 host sshd[4]: Accepted password for alice from {ip_good1} port 22 ssh2",
        f"Feb 20 12:01:01 host sshd[5]: Failed password for bob from {ip_short} port 22 ssh2",
        f"Feb 20 12:01:02 host sshd[6]: Failed password for bob from {ip_short} port 22 ssh2",
        f"Feb 20 12:01:03 host sshd[7]: Accepted password for bob from {ip_short} port 22 ssh2",
        f"Feb 20 12:02:01 host sshd[8]: Failed password for carol from {ip_early} port 22 ssh2",
        f"Feb 20 12:02:02 host sshd[9]: Failed password for carol from {ip_early} port 22 ssh2",
        f"Feb 20 12:02:03 host sshd[10]: Accepted password for carol from {ip_early} port 22 ssh2",
        f"Feb 20 12:02:04 host sshd[11]: Failed password for carol from {ip_early} port 22 ssh2",
        f"Feb 20 12:03:01 host sshd[12]: Failed password for dave from {ip_mixed} port 22 ssh2",
        f"Feb 20 12:03:02 host sshd[13]: Failed password for dan from {ip_mixed} port 22 ssh2",
        f"Feb 20 12:03:03 host sshd[14]: Failed password for dave from {ip_mixed} port 22 ssh2",
        f"Feb 20 12:03:04 host sshd[15]: Accepted password for dave from {ip_mixed} port 22 ssh2",
        f"Feb 20 12:04:01 host sshd[16]: Failed password for eve from {ip_good2} port 22 ssh2",
        f"Feb 20 12:04:02 host sshd[17]: Failed password for eve from {ip_good2} port 22 ssh2",
        f"Feb 20 12:04:03 host sshd[18]: Failed password for eve from {ip_good2} port 22 ssh2",
        f"Feb 20 12:04:04 host sshd[19]: Failed password for eve from {ip_good2} port 22 ssh2",
        f"Feb 20 12:04:05 host sshd[20]: Accepted password for eve from {ip_good2} port 22 ssh2",
        f"Feb 20 12:05:01 host sshd[21]: Accepted publickey for nobody from 203.0.113.9 port 22 ssh2",
    ]
    with open(auth, "w") as f:
        f.write("\n".join(lines) + "\n")

    names = {
        "good1": f"exact_tmp_{suffix}",
        "good2": f"also_exact_{suffix}",
        "nonsuid": f"nonsuid_{suffix}",
        "list": f"rpath_list_{suffix}",
        "slash": f"tmp_slash_{suffix}",
        "plain": f"plain_suid_{suffix}",
        "text": f"text_suid_{suffix}",
    }

    def elf(name):
        path = os.path.join(binaries, names[name])
        shutil.copy2("/bin/true", path)
        return path

    good1 = elf("good1")
    good2 = elf("good2")
    nonsuid = elf("nonsuid")
    rpath_list = elf("list")
    tmp_slash = elf("slash")
    plain = elf("plain")

    for path, rpath in ((good1, "/tmp"), (good2, "/tmp"),
                        (nonsuid, "/tmp"), (rpath_list, "/tmp:/opt/lib"),
                        (tmp_slash, "/tmp/")):
        subprocess.run(["patchelf", "--set-rpath", rpath, path], check=True)

    for path in (good1, good2, rpath_list, tmp_slash, plain):
        os.chmod(path, 0o4755)
    os.chmod(nonsuid, 0o0755)

    text_path = os.path.join(binaries, names["text"])
    with open(text_path, "w") as f:
        f.write("not an ELF file\n")
    os.chmod(text_path, 0o4755)

    assert run([AUDIT, auth]).returncode != 0, "audit_script.sh must reject fewer than two arguments."
    assert run([AUDIT, auth, binaries, "extra"]).returncode != 0, "audit_script.sh must reject more than two arguments."

    result = run([AUDIT, auth, binaries], timeout=30)
    assert result.returncode == 0, (
        f"audit_script.sh failed on generated inputs.\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )

    with open(f"{HOME}/breached_ips.txt") as f:
        actual_ips = [line.strip() for line in f if line.strip()]
    assert sorted(actual_ips) == sorted([ip_good1, ip_good2])

    with open(f"{HOME}/vulnerable_binaries.txt") as f:
        actual_bins = [line.strip() for line in f if line.strip()]
    assert sorted(actual_bins) == sorted([names["good1"], names["good2"]])


def test_wrapper_really_executes_command_in_restricted_sandbox():
    token = uuid.uuid4().hex
    marker = f"{HOME}/.sandbox-marker-{token}"
    usr_probe = f"/usr/.sandbox-write-{token}"

    listener = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    listener.bind(("127.0.0.1", 0))
    listener.listen(1)
    port = listener.getsockname()[1]

    with open(AUDIT, "rb") as f:
        original = f.read()
    original_mode = stat.S_IMODE(os.stat(AUDIT).st_mode)

    probe = f'''#!/bin/bash
set -u
[[ "$#" -eq 2 ]] || exit 40
[[ "$1" == "/home/user/auth.log" ]] || exit 41
[[ "$2" == "/home/user/binaries" ]] || exit 42
for p in /proc /sys /etc /root /var /tmp /run /opt /mnt /srv /media; do
    [[ ! -e "$p" ]] || exit 50
done
[[ -c /dev/null ]] || exit 51
if : > "{usr_probe}" 2>/dev/null; then
    exit 52
fi
if (exec 3<>/dev/tcp/127.0.0.1/{port}) 2>/dev/null; then
    exit 53
fi
printf '%s\\n' '{token}' > '{marker}' || exit 54
'''

    try:
        with open(AUDIT, "w") as f:
            f.write(probe)
        os.chmod(AUDIT, 0o755)
        if os.path.exists(marker):
            os.unlink(marker)

        result = run([WRAPPER], timeout=30)
        assert result.returncode == 0, (
            f"Sandbox probe failed with status {result.returncode}.\n"
            f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )
        assert os.path.isfile(marker), "The fixed audit command was not executed inside the sandbox."
        with open(marker) as f:
            assert f.read().strip() == token
    finally:
        listener.close()
        with open(AUDIT, "wb") as f:
            f.write(original)
        os.chmod(AUDIT, original_mode)
        for path in (marker, usr_probe):
            try:
                os.unlink(path)
            except FileNotFoundError:
                pass
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
