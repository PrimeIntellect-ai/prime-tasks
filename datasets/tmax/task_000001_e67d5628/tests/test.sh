#!/bin/bash
set -u
mkdir -p /logs/verifier

cat <<'PY' > /tmp/verify_final_state.py
import os
import re
import shlex
import shutil
import socket
import stat
import subprocess
import tempfile
import threading
import time


def check(cond, msg):
    if not cond:
        raise AssertionError(msg)


def run(cmd, **kwargs):
    return subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=kwargs.pop("timeout", 15), **kwargs)


def test_restore_and_fstab():
    source = "/app/backup_data/manifest.txt"
    restored = "/home/user/restore_mnt/manifest.txt"
    fstab = "/home/user/local_fstab"
    check(os.path.isdir("/home/user/restore_mnt"), "restore_mnt is not a directory")
    check(os.path.isfile(restored), "restored manifest is missing")
    with open(source, "rb") as f:
        expected = f.read()
    with open(restored, "rb") as f:
        actual = f.read()
    check(actual == expected, "restore_mnt does not contain the original manifest data")
    check(os.path.isfile(fstab), "local_fstab is missing")
    with open(fstab, encoding="utf-8") as f:
        lines = [line.strip() for line in f]
    check("/app/backup_data /home/user/restore_mnt none bind 0 0" in lines,
          "exact bind entry is missing from local_fstab")


def test_library():
    directory = "/app/libnetconf"
    source = os.path.join(directory, "net_parse.c")
    makefile = os.path.join(directory, "Makefile")
    archive = os.path.join(directory, "libnetconf.a")
    check(os.path.isfile(source), "net_parse.c is missing")
    check(os.path.isfile(makefile), "Makefile is missing")

    with open(source, encoding="utf-8") as f:
        text = f.read()
    uncommented = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    uncommented = re.sub(r"//.*", "", uncommented)
    check(re.search(r"^\s*#\s*include\s*[<\"]arpa/inet\.h[>\"]", uncommented, re.M) is not None,
          "net_parse.c does not include arpa/inet.h")

    for name in ("libnetconf.a", "net_parse.o"):
        try:
            os.unlink(os.path.join(directory, name))
        except FileNotFoundError:
            pass
    proc = run(["make"], cwd=directory)
    output = proc.stdout + proc.stderr
    check(proc.returncode == 0, "make failed:\n" + output.decode(errors="replace"))
    check(re.search(rb"warning\s*:", output, re.I) is None,
          "library build emitted a warning:\n" + output.decode(errors="replace"))
    check(os.path.isfile(archive), "make did not create libnetconf.a")
    with open(archive, "rb") as f:
        check(f.read(8) == b"!<arch>\n", "libnetconf.a is not a static archive")
    ar = run(["ar", "t", archive])
    check(ar.returncode == 0 and ar.stdout.strip(), "libnetconf.a has no valid object members")

    with tempfile.TemporaryDirectory() as td:
        probe = os.path.join(td, "probe.c")
        exe = os.path.join(td, "probe")
        with open(probe, "w", encoding="utf-8") as f:
            f.write('int net_parse_rule(const char *);\nint main(void) { return net_parse_rule("rule"); }\n')
        linked = run(["gcc", "-Wall", "-Werror", probe, archive, "-o", exe])
        check(linked.returncode == 0, "libnetconf.a cannot be linked:\n" + linked.stderr.decode(errors="replace"))
        executed = run([exe])
        check(executed.returncode == 0, "linked net_parse_rule probe failed")


def test_locale_timezone_and_manifest():
    cmd = r'''set -a
[ -f "$HOME/.profile" ] && . "$HOME/.profile"
[ -f "$HOME/.bashrc" ] && . "$HOME/.bashrc"
printf '__ENV_CHECK__%s|%s|%s\n' "${LANG-}" "${LC_ALL-}" "${TZ-}"
'''
    proc = run(["runuser", "-u", "user", "--", "env", "HOME=/home/user", "bash", "-c", cmd])
    check(proc.returncode == 0, "could not load the user environment")
    matches = re.findall(rb"__ENV_CHECK__([^|\n]*)\|([^|\n]*)\|([^\n]*)", proc.stdout)
    check(matches, "locale/timezone settings were not found in the user environment")
    lang, lc_all, tz = [v.decode() for v in matches[-1]]
    effective_locale = lc_all or lang
    check(effective_locale == "C.UTF-8", "effective locale is not C.UTF-8")
    check(tz == "America/New_York", "TZ is not America/New_York")

    with open("/home/user/restore_mnt/manifest.txt", "r", encoding="utf-8") as f:
        expected = [line for line in f if len(line.split()) >= 3 and line.split()[2] == "RESTORED"]
    check(os.path.isfile("/home/user/processed_manifest.txt"), "processed_manifest.txt is missing")
    with open("/home/user/processed_manifest.txt", "r", encoding="utf-8") as f:
        actual = f.readlines()
    check(actual == expected, "processed_manifest.txt is not the exact RESTORED-line extraction")


def expected_result(data):
    line = data.split(b"\n", 1)[0]
    valid = (len(line) >= 12 and line[:6] == b"ROUTE:" and
             all(48 <= c <= 57 for c in line[6:10]) and
             line[10:11] == b"." and 65 <= line[11] <= 90)
    return b"VALID\n" if valid else b"INVALID\n"


def exercise_validator(path):
    cases = [
        b"", b"ROUTE:1234.A\n", b"ROUTE:0000.Z", b"ROUTE:123.A\n",
        b"ROUTE:12345.A\n", b"ROUTE:1234.a\n", b"route:1234.A\n",
        b"ROUTE:1234.\n", b"XROUTE:1234.A\n", b"ROUTE:1234.AB\n",
        b"ROUTE:9999.Z trailing text\n", b"ROUTE:1234.A\nROUTE:12.X\n",
        b"ROUTE:12x4.A\n", b" ROUTE:1234.A\n"
    ]
    alphabet = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789:._- "
    seed = 0x5A17
    for i in range(500):
        seed = (1103515245 * seed + 12345) & 0x7fffffff
        length = seed % 129
        buf = bytearray()
        for _ in range(length):
            seed = (1103515245 * seed + 12345) & 0x7fffffff
            buf.append(alphabet[seed % len(alphabet)])
        if i % 7 == 0 and length >= 12:
            buf[:12] = b"ROUTE:1234.A"
        cases.append(bytes(buf) + (b"\n" if i % 2 else b""))
    for data in cases:
        proc = run([path], input=data, timeout=2)
        check(proc.returncode == 0, "validator did not exit with status 0 for %r" % data)
        check(proc.stdout == expected_result(data),
              "wrong validator output for %r: got %r" % (data, proc.stdout))
        check(proc.stderr == b"", "validator wrote unexpected stderr output")


def test_validator():
    source = "/home/user/validate_ip_format.c"
    binary = "/home/user/validate_ip_format"
    check(os.path.isfile(source) and not os.path.islink(source), "validator C source is missing or not a regular file")
    check(os.path.isfile(binary) and not os.path.islink(binary), "validator binary is missing or not a regular file")
    check(os.access(binary, os.X_OK), "validator binary is not executable")
    with open(binary, "rb") as f:
        check(f.read(4) == b"\x7fELF", "validate_ip_format is not a compiled executable")

    # Remove any recreated reference paths before execution so a submitted wrapper cannot invoke them.
    for path in ("/opt/oracle/oracle.c", "/opt/oracle/validate_ip_format_oracle"):
        try:
            os.unlink(path)
        except FileNotFoundError:
            pass

    with tempfile.TemporaryDirectory() as td:
        rebuilt = os.path.join(td, "validate_ip_format")
        proc = run(["gcc", "-std=c11", "-Wall", "-Wextra", source, "-o", rebuilt])
        check(proc.returncode == 0, "validator source does not compile:\n" + proc.stderr.decode(errors="replace"))
        check(re.search(rb"warning\s*:", proc.stderr, re.I) is None,
              "validator source compiles with warnings:\n" + proc.stderr.decode(errors="replace"))
        exercise_validator(rebuilt)
    exercise_validator(binary)


def test_ssh_tunnel():
    command_file = "/home/user/ssh_tunnel_cmd.txt"
    check(os.path.isfile(command_file), "ssh_tunnel_cmd.txt is missing")
    with open(command_file, encoding="utf-8") as f:
        content = f.read().strip()
    argv = shlex.split(content)
    check(argv and argv[0] == "ssh", "tunnel command must invoke ssh")
    check(argv[-1] == "user@127.0.0.1", "tunnel destination must be user@127.0.0.1")

    has_n = any(token.startswith("-") and not token.startswith("-L") and "N" in token[1:] for token in argv[1:-1])
    forwards = []
    i = 1
    while i < len(argv) - 1:
        token = argv[i]
        if token == "-L":
            check(i + 1 < len(argv) - 1, "-L has no forwarding argument")
            forwards.append(argv[i + 1])
            i += 2
            continue
        if token.startswith("-L") and len(token) > 2:
            forwards.append(token[2:])
        i += 1
    accepted = {"9090:127.0.0.1:8080", "127.0.0.1:9090:127.0.0.1:8080"}
    check(has_n, "ssh command is missing the -N tunnel-only option")
    check(any(value in accepted for value in forwards), "ssh command lacks the exact 9090-to-127.0.0.1:8080 forwarding")

    subprocess.run(["pkill", "-u", "user", "-x", "ssh"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run(["/usr/sbin/sshd"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    os.makedirs("/home/user/.ssh", exist_ok=True)
    scan = run(["ssh-keyscan", "-H", "127.0.0.1"], timeout=5)
    check(scan.returncode == 0 and scan.stdout, "could not obtain the local SSH host key")
    known_hosts = "/home/user/.ssh/known_hosts"
    with open(known_hosts, "wb") as f:
        f.write(scan.stdout)
    os.chown(known_hosts, 1000, 1000)
    os.chmod(known_hosts, 0o600)

    ready = threading.Event()
    server_error = []
    nonce = b"tunnel-validation-7f31"

    def endpoint():
        try:
            with socket.socket() as srv:
                srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
                srv.bind(("127.0.0.1", 8080))
                srv.listen(1)
                srv.settimeout(10)
                ready.set()
                conn, _ = srv.accept()
                with conn:
                    data = conn.recv(4096)
                    conn.sendall(data)
        except Exception as exc:
            server_error.append(exc)
            ready.set()

    thread = threading.Thread(target=endpoint, daemon=True)
    thread.start()
    ready.wait(3)
    check(not server_error, "could not start validation endpoint: %s" % server_error)

    def demote():
        os.setgid(1000)
        os.setuid(1000)

    proc = subprocess.Popen(argv, cwd="/home/user", env={**os.environ, "HOME": "/home/user"},
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE, preexec_fn=demote)
    try:
        received = None
        deadline = time.time() + 10
        while time.time() < deadline:
            if proc.poll() is not None and proc.returncode != 0:
                break
            try:
                with socket.create_connection(("127.0.0.1", 9090), timeout=0.5) as client:
                    client.sendall(nonce)
                    received = client.recv(4096)
                    break
            except OSError:
                time.sleep(0.2)
        check(received == nonce, "saved SSH command did not create a working tunnel")
    finally:
        if proc.poll() is None:
            proc.terminate()
            try:
                proc.wait(timeout=2)
            except subprocess.TimeoutExpired:
                proc.kill()
        subprocess.run(["pkill", "-u", "user", "-x", "ssh"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def main():
    test_restore_and_fstab()
    test_library()
    test_locale_timezone_and_manifest()
    test_validator()
    test_ssh_tunnel()


if __name__ == "__main__":
    main()
PY

if python3 /tmp/verify_final_state.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
