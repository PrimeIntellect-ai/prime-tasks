#!/bin/bash
mkdir -p /logs/verifier
echo "0" > /logs/verifier/reward.txt

QUARANTINED_ORACLE="/dev/shm/.header_parser_quarantined_$$"
if [ -e /app/header_parser ]; then
    mv /app/header_parser "$QUARANTINED_ORACLE"
    chmod 000 "$QUARANTINED_ORACLE"
fi
restore_oracle() {
    if [ -e "$QUARANTINED_ORACLE" ]; then
        chmod 755 "$QUARANTINED_ORACLE"
        mv "$QUARANTINED_ORACLE" /app/header_parser
    fi
}
trap restore_oracle EXIT

cat << 'HOOK_EOF' > /tmp/rename_audit.c
#define _GNU_SOURCE
#include <dlfcn.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>

static void record_event(int olddirfd, const char *oldpath, const char *newpath) {
    const char *log = getenv("RENAME_AUDIT_LOG");
    if (!log || !oldpath || !newpath) return;
    struct stat st;
    long long size = -1;
    if (fstatat(olddirfd, oldpath, &st, 0) == 0) size = (long long)st.st_size;
    int fd = open(log, O_WRONLY | O_CREAT | O_APPEND, 0666);
    if (fd >= 0) {
        dprintf(fd, "%s\t%s\t%lld\n", oldpath, newpath, size);
        close(fd);
    }
}

int rename(const char *oldpath, const char *newpath) {
    static int (*real_rename)(const char *, const char *);
    if (!real_rename) real_rename = dlsym(RTLD_NEXT, "rename");
    record_event(AT_FDCWD, oldpath, newpath);
    return real_rename(oldpath, newpath);
}

int renameat(int olddirfd, const char *oldpath, int newdirfd, const char *newpath) {
    static int (*real_renameat)(int, const char *, int, const char *);
    if (!real_renameat) real_renameat = dlsym(RTLD_NEXT, "renameat");
    record_event(olddirfd, oldpath, newpath);
    return real_renameat(olddirfd, oldpath, newdirfd, newpath);
}

int renameat2(int olddirfd, const char *oldpath, int newdirfd, const char *newpath, unsigned int flags) {
    static int (*real_renameat2)(int, const char *, int, const char *, unsigned int);
    if (!real_renameat2) real_renameat2 = dlsym(RTLD_NEXT, "renameat2");
    record_event(olddirfd, oldpath, newpath);
    return real_renameat2(olddirfd, oldpath, newdirfd, newpath, flags);
}
HOOK_EOF

gcc -shared -fPIC -O2 -o /tmp/rename_audit.so /tmp/rename_audit.c -ldl 2>/dev/null

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import pwd
import random
import shutil
import struct
import subprocess
import tempfile
import uuid
import zlib
from pathlib import Path

USER = pwd.getpwnam("user")
AGENT_PARSER = Path("/home/user/parse_header.sh")
ORGANIZER = Path("/home/user/organize_data.sh")
RAW = Path("/home/user/raw_data")
ORG = Path("/home/user/organized_data")
LOG = Path("/home/user/corrupt_files.log")
HOOK = "/tmp/rename_audit.so"


def demote():
    os.setgroups([])
    os.setgid(USER.pw_gid)
    os.setuid(USER.pw_uid)


def expected_result(data):
    if len(data) < 16:
        return 0, "ERROR: TOO_SHORT\n", ""
    if data[:4] != b"PDAT":
        return 0, "ERROR: BAD_MAGIC\n", ""
    ts = struct.unpack_from("<I", data, 4)[0]
    dev = struct.unpack_from(">H", data, 8)[0]
    exp = struct.unpack_from("<H", data, 10)[0]
    stored_crc = struct.unpack_from("<I", data, 12)[0]
    payload = data[16:]
    calculated_crc = (zlib.crc32(payload) & 0xffffffff) if payload else 0
    integrity = "VALID" if stored_crc == calculated_crc else "INVALID"
    return 0, f"TS:{ts} DEV:{dev} EXP:{exp} INTEGRITY:{integrity}\n", ""


def run_as_user(argv, **kwargs):
    env = os.environ.copy()
    env.update(kwargs.pop("env", {}))
    env["LD_PRELOAD"] = HOOK
    return subprocess.run(
        argv,
        env=env,
        preexec_fn=demote,
        capture_output=True,
        text=True,
        timeout=kwargs.pop("timeout", 30),
        **kwargs,
    )


def make_archive(ts, dev, exp, payload, valid=True):
    crc = zlib.crc32(payload) & 0xffffffff if payload else 0
    if not valid:
        crc ^= 0xffffffff
    return b"PDAT" + struct.pack("<I", ts) + struct.pack(">H", dev) + struct.pack("<H", exp) + struct.pack("<I", crc) + payload


def test_fuzz_equivalence_without_proprietary_binary():
    assert AGENT_PARSER.exists(), f"Agent script not found at {AGENT_PARSER}"
    assert os.access(AGENT_PARSER, os.X_OK), f"Agent script at {AGENT_PARSER} is not executable"
    assert AGENT_PARSER.is_file(), "parse_header.sh must be a file"

    no_arg = run_as_user([str(AGENT_PARSER)])
    assert (no_arg.returncode, no_arg.stdout, no_arg.stderr) == (1, "", "")
    missing = run_as_user([str(AGENT_PARSER), "/tmp/definitely_missing_pdat_file"])
    assert (missing.returncode, missing.stdout, missing.stderr) == (1, "", "")

    random.seed(42)
    for i in range(500):
        category = random.random()
        if category < 0.2:
            data = bytes(random.getrandbits(8) for _ in range(random.randint(0, 15)))
        elif category < 0.4:
            length = random.randint(16, 1024)
            data = bytearray(random.getrandbits(8) for _ in range(length))
            while data[:4] == b"PDAT":
                data[:4] = bytes(random.getrandbits(8) for _ in range(4))
            data = bytes(data)
        else:
            length = random.randint(16, 1024)
            data = bytearray(random.getrandbits(8) for _ in range(length))
            data[:4] = b"PDAT"
            payload = data[16:]
            crc = (zlib.crc32(payload) & 0xffffffff) if payload else 0
            if random.random() < 0.5:
                crc ^= 0xffffffff
            struct.pack_into("<I", data, 12, crc)
            data = bytes(data)

        fd, path = tempfile.mkstemp(prefix="pdat_fuzz_")
        try:
            os.write(fd, data)
            os.close(fd)
            os.chmod(path, 0o644)
            expected_rc, expected_out, expected_err = expected_result(data)
            proc = run_as_user([str(AGENT_PARSER), path])
            assert proc.returncode == expected_rc, f"Exit mismatch on input {i}"
            assert proc.stdout == expected_out, f"Stdout mismatch on input {i}: {proc.stdout!r} != {expected_out!r}"
            assert proc.stderr == expected_err, f"Stderr mismatch on input {i}: {proc.stderr!r}"
        finally:
            try:
                os.close(fd)
            except OSError:
                pass
            os.unlink(path)


def test_original_organization_state():
    assert ORG.exists(), f"Organized data directory not found at {ORG}"
    expected_corrupt = set()
    expected_organized = []

    for dat_file in RAW.glob("*.dat"):
        data = dat_file.read_bytes()
        _, out, _ = expected_result(data)
        stripped = out.strip()
        if stripped.startswith("ERROR:") or "INTEGRITY:INVALID" in stripped:
            expected_corrupt.add(dat_file.name)
        else:
            parts = stripped.split()
            ts = parts[0].split(":", 1)[1]
            dev = parts[1].split(":", 1)[1]
            exp = parts[2].split(":", 1)[1]
            expected_organized.append((dat_file, ORG / f"DEV_{dev}" / f"EXP_{exp}" / f"{ts}.dat"))

    if expected_corrupt:
        assert LOG.exists(), "corrupt_files.log does not exist"
        contents = LOG.read_text(errors="replace")
        for name in expected_corrupt:
            assert name in contents, f"Expected {name} in corrupt_files.log"

    for src, dst in expected_organized:
        assert dst.exists(), f"Expected organized file not found at {dst}"
        assert src.read_bytes() == dst.read_bytes(), f"File content mismatch for {dst}"


def test_organizer_executes_parser_and_uses_atomic_tmp_rename():
    assert ORGANIZER.exists(), f"Organizer script not found at {ORGANIZER}"
    assert ORGANIZER.is_file(), "organize_data.sh must be a file"
    assert os.access(ORGANIZER, os.X_OK), "organize_data.sh is not executable"

    token = uuid.uuid4().hex
    holding = Path(tempfile.mkdtemp(prefix="organization_backup_"))
    parser_real = Path(f"/home/user/.parse_header_real_{token}")
    calls = Path(f"/tmp/parser_calls_{token}")
    renames = Path(f"/tmp/rename_calls_{token}")
    calls.write_text("")
    renames.write_text("")
    os.chmod(calls, 0o666)
    os.chmod(renames, 0o666)

    backups = {}
    try:
        for path in (RAW, ORG, LOG):
            if path.exists() or path.is_symlink():
                target = holding / path.name
                shutil.move(str(path), str(target))
                backups[path] = target

        shutil.move(str(AGENT_PARSER), str(parser_real))
        wrapper = f'''#!/bin/bash\nprintf '%s\\n' "$1" >> {calls}\nexec {parser_real} "$@"\n'''
        AGENT_PARSER.write_text(wrapper)
        os.chmod(AGENT_PARSER, 0o755)

        RAW.mkdir(parents=True)
        ORG.mkdir(parents=True)
        for path in (RAW, ORG):
            os.chown(path, USER.pw_uid, USER.pw_gid)

        cases = {
            "valid_a.dat": make_archive(123456, 258, 513, b"alpha" * 1000, True),
            "valid_empty.dat": make_archive(0xffffffff, 65535, 0, b"", True),
            "invalid_crc.dat": make_archive(77, 8, 9, b"bad payload", False),
            "bad_magic.dat": b"NOPE" + b"x" * 40,
            "too_short.dat": b"PDATshort",
        }
        for name, data in cases.items():
            path = RAW / name
            path.write_bytes(data)
            os.chown(path, USER.pw_uid, USER.pw_gid)
            os.chmod(path, 0o644)
        (RAW / "ignored.txt").write_text("not a dat file")
        os.chown(RAW / "ignored.txt", USER.pw_uid, USER.pw_gid)

        proc = run_as_user(
            [str(ORGANIZER)],
            env={"RENAME_AUDIT_LOG": str(renames)},
            timeout=60,
            cwd="/home/user",
        )
        assert proc.returncode == 0, f"organize_data.sh failed: stdout={proc.stdout!r} stderr={proc.stderr!r}"

        called = [Path(line.strip()).name for line in calls.read_text().splitlines() if line.strip()]
        for name in cases:
            assert name in called, f"organize_data.sh did not process {name} through parse_header.sh"
        assert "ignored.txt" not in called, "organize_data.sh passed a non-.dat file to the parser"

        valid_expected = {
            ORG / "DEV_258" / "EXP_513" / "123456.dat": RAW / "valid_a.dat",
            ORG / "DEV_65535" / "EXP_0" / "4294967295.dat": RAW / "valid_empty.dat",
        }
        for dst, src in valid_expected.items():
            assert dst.exists(), f"Expected organized file not found at {dst}"
            assert dst.read_bytes() == src.read_bytes(), f"File content mismatch for {dst}"

        assert LOG.exists(), "corrupt_files.log was not created"
        log_lines = LOG.read_text(errors="replace").splitlines()
        for name in ("invalid_crc.dat", "bad_magic.dat", "too_short.dat"):
            assert any(name in line for line in log_lines), f"Expected {name} in corrupt_files.log"

        assert (ORG / ".tmp").is_dir(), "organized_data/.tmp was not created"
        events = []
        for line in renames.read_text().splitlines():
            fields = line.split("\t")
            if len(fields) == 3:
                try:
                    events.append((fields[0], fields[1], int(fields[2])))
                except ValueError:
                    pass

        for dst, src in valid_expected.items():
            matching = [e for e in events if os.path.abspath(e[1]) == str(dst)]
            assert matching, f"No atomic rename into final destination {dst} was observed"
            assert any(
                os.path.abspath(old).startswith(str(ORG / ".tmp") + os.sep)
                and size == src.stat().st_size
                for old, _, size in matching
            ), f"{dst} was not renamed from a complete temporary file in organized_data/.tmp"
    finally:
        if AGENT_PARSER.exists() or AGENT_PARSER.is_symlink():
            AGENT_PARSER.unlink()
        if parser_real.exists():
            shutil.move(str(parser_real), str(AGENT_PARSER))
        for path in (RAW, ORG, LOG):
            if path.is_dir() and not path.is_symlink():
                shutil.rmtree(path)
            elif path.exists() or path.is_symlink():
                path.unlink()
        for path, backup in backups.items():
            if backup.exists() or backup.is_symlink():
                shutil.move(str(backup), str(path))
        shutil.rmtree(holding, ignore_errors=True)
        calls.unlink(missing_ok=True)
        renames.unlink(missing_ok=True)
TEST_EOF

if [ -f /tmp/rename_audit.so ] && python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
