#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import pwd
import shutil
import stat
import subprocess
import tempfile
import uuid

HOME = "/home/user"
IMPLANT = "/home/user/implant"
FLAG = "/home/user/flag.txt"
EXPECTED_FLAG = "FLAG{JWT_byp4ss_r3c0v3ry}"
USER = pwd.getpwnam("user")


def as_user():
    os.setgroups([])
    os.setgid(USER.pw_gid)
    os.setuid(USER.pw_uid)


def run_as_user(argv, cwd=None, env=None, timeout=30):
    return subprocess.run(
        argv,
        cwd=cwd,
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=timeout,
        preexec_fn=as_user,
    )


def compile_candidates():
    candidates = []
    errors = []

    standalone = "/home/user/recover.rs"
    if os.path.isfile(standalone):
        outdir = tempfile.mkdtemp(prefix="recover-standalone-")
        os.chown(outdir, USER.pw_uid, USER.pw_gid)
        output = os.path.join(outdir, "recover")
        result = run_as_user(["rustc", standalone, "-O", "-o", output], cwd=HOME, timeout=120)
        if result.returncode == 0 and os.path.isfile(output):
            candidates.append((output, HOME))
        else:
            errors.append("recover.rs did not compile: " + result.stderr.decode(errors="replace"))

    manifest = "/home/user/recover/Cargo.toml"
    if os.path.isfile(manifest):
        target_dir = tempfile.mkdtemp(prefix="recover-cargo-")
        os.chown(target_dir, USER.pw_uid, USER.pw_gid)
        env = os.environ.copy()
        env["CARGO_TARGET_DIR"] = target_dir
        result = run_as_user(
            ["cargo", "build", "--release", "--manifest-path", manifest, "--message-format=json"],
            cwd="/home/user/recover",
            env=env,
            timeout=180,
        )
        if result.returncode == 0:
            for line in result.stdout.splitlines():
                try:
                    message = json.loads(line)
                except Exception:
                    continue
                executable = message.get("executable")
                kinds = message.get("target", {}).get("kind", [])
                if executable and "bin" in kinds and os.path.isfile(executable):
                    item = (executable, "/home/user/recover")
                    if item not in candidates:
                        candidates.append(item)
        else:
            errors.append("Cargo project did not compile: " + result.stderr.decode(errors="replace"))

    assert candidates, "No submitted Rust program could be compiled. " + "\n".join(errors)
    return candidates


def build_probe(path, nonce):
    source = r'''
use std::io::{self, Read};

fn decode(s: &str) -> Option<Vec<u8>> {
    let b = s.as_bytes();
    if b.is_empty() || b.len() % 4 != 0 { return None; }
    let val = |c: u8| -> Option<u8> {
        match c {
            b'A'..=b'Z' => Some(c - b'A'),
            b'a'..=b'z' => Some(c - b'a' + 26),
            b'0'..=b'9' => Some(c - b'0' + 52),
            b'+' => Some(62),
            b'/' => Some(63),
            _ => None,
        }
    };
    let mut out = Vec::new();
    for (i, chunk) in b.chunks(4).enumerate() {
        let last = i + 1 == b.len() / 4;
        let pad = if chunk[2] == b'=' { 2 } else if chunk[3] == b'=' { 1 } else { 0 };
        if pad > 0 && !last { return None; }
        if chunk[2] == b'=' && chunk[3] != b'=' { return None; }
        let a = val(chunk[0])? as u32;
        let c = val(chunk[1])? as u32;
        let d = if chunk[2] == b'=' { 0 } else { val(chunk[2])? as u32 };
        let e = if chunk[3] == b'=' { 0 } else { val(chunk[3])? as u32 };
        if pad == 2 && (c & 15) != 0 { return None; }
        if pad == 1 && (d & 3) != 0 { return None; }
        let n = (a << 18) | (c << 12) | (d << 6) | e;
        out.push((n >> 16) as u8);
        if pad < 2 { out.push((n >> 8) as u8); }
        if pad < 1 { out.push(n as u8); }
    }
    Some(out)
}

fn compact_json(v: Vec<u8>) -> Option<String> {
    let s = String::from_utf8(v).ok()?;
    Some(s.chars().filter(|c| !c.is_ascii_whitespace()).collect())
}

fn main() {
    let mut input = String::new();
    if io::stdin().read_to_string(&mut input).is_err() { return; }
    let parts: Vec<&str> = input.trim().split('.').collect();
    if parts.len() != 3 || parts[2].is_empty() { return; }
    let header = decode(parts[0]).and_then(compact_json);
    let payload = decode(parts[1]).and_then(compact_json);
    if header.as_deref() == Some("{\"alg\":\"none\"}") &&
       payload.as_deref() == Some("{\"action\":\"extract\"}") {
        println!("%s");
    }
}
''' % nonce

    src = tempfile.NamedTemporaryFile(prefix="implant-probe-", suffix=".rs", delete=False)
    try:
        src.write(source.encode())
        src.close()
        os.chmod(src.name, 0o600)
        result = subprocess.run(
            ["rustc", src.name, "-O", "-o", path],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=120,
        )
        assert result.returncode == 0, "Could not build verifier probe: " + result.stderr.decode(errors="replace")
        os.chown(path, 0, 0)
        os.chmod(path, 0o711)
    finally:
        try:
            os.unlink(src.name)
        except FileNotFoundError:
            pass


def test_flag_file_exists():
    flag_path = "/home/user/flag.txt"
    assert os.path.exists(flag_path), f"The file {flag_path} does not exist. Did your program write to it?"
    assert os.path.isfile(flag_path), f"{flag_path} is not a regular file."


def test_flag_content():
    flag_path = "/home/user/flag.txt"
    assert os.path.exists(flag_path), f"Cannot check content because {flag_path} does not exist."

    with open(flag_path, "r") as f:
        content = f.read()

    expected_flag = "FLAG{JWT_byp4ss_r3c0v3ry}"
    assert expected_flag in content, f"The file {flag_path} does not contain the correct flag. Found: {content.strip()}"


def test_recover_rust_code_exists():
    standalone_path = "/home/user/recover.rs"
    cargo_path = "/home/user/recover/src/main.rs"

    assert os.path.exists(standalone_path) or os.path.exists(cargo_path), \
        "Could not find the Rust program at /home/user/recover.rs or /home/user/recover/src/main.rs"


def test_compiled_recovery_program_drives_implant_and_captures_stdout():
    candidates = compile_candidates()
    assert os.path.isfile(IMPLANT), f"{IMPLANT} is missing"

    original = open(IMPLANT, "rb").read()
    original_stat = os.stat(IMPLANT)
    failures = []

    def restore_implant():
        tmp = IMPLANT + ".verifier-restore"
        with open(tmp, "wb") as f:
            f.write(original)
        os.chown(tmp, original_stat.st_uid, original_stat.st_gid)
        os.chmod(tmp, stat.S_IMODE(original_stat.st_mode))
        os.replace(tmp, IMPLANT)

    for executable, cwd in candidates:
        nonce = "RECOVER_PROBE_" + uuid.uuid4().hex
        probe_tmp = IMPLANT + ".verifier-probe"
        try:
            build_probe(probe_tmp, nonce)
            os.replace(probe_tmp, IMPLANT)
            try:
                os.unlink(FLAG)
            except FileNotFoundError:
                pass

            result = run_as_user([executable], cwd=cwd, timeout=30)
            if result.returncode != 0:
                failures.append(f"{executable} exited with {result.returncode} during the probe")
                continue
            if not os.path.isfile(FLAG):
                failures.append(f"{executable} did not create {FLAG}")
                continue
            with open(FLAG, "rb") as f:
                captured = f.read()
            expected_probe_output = (nonce + "\n").encode()
            if captured != expected_probe_output:
                failures.append(f"{executable} did not write the probe implant's stdout exactly")
                continue

            restore_implant()
            try:
                os.unlink(FLAG)
            except FileNotFoundError:
                pass
            result = run_as_user([executable], cwd=cwd, timeout=30)
            if result.returncode != 0 or not os.path.isfile(FLAG):
                failures.append(f"{executable} failed when run with the recovered implant")
                continue
            with open(FLAG, "r", errors="replace") as f:
                final_content = f.read()
            if EXPECTED_FLAG not in final_content:
                failures.append(f"{executable} did not recover the expected flag")
                continue
            return
        finally:
            try:
                os.unlink(probe_tmp)
            except FileNotFoundError:
                pass
            restore_implant()

    assert False, "No compiled Rust submission passed the execution checks: " + "; ".join(failures)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
