#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import shutil
import stat
import subprocess
import tarfile
import tempfile
import uuid

import pytest

USER_UID = 1000
USER_GID = 1000


def run_as_user(args, timeout=15, env=None):
    cmd = ["runuser", "-u", "user", "--"] + list(args)
    return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout, env=env)


def test_expect_script_exists():
    assert os.path.isfile("/home/user/fetch.exp"), "Expect script /home/user/fetch.exp does not exist."


def test_tarball_extracted():
    assert os.path.isfile("/home/user/mail_data.tar"), "Tarball /home/user/mail_data.tar was not generated."
    assert os.path.isfile("/home/user/mail_data/postfix/main.cf"), "Tarball was not extracted properly to /home/user/mail_data/postfix/main.cf."
    assert os.path.isfile("/home/user/mail_data/dovecot/dovecot.conf"), "Tarball was not extracted properly to /home/user/mail_data/dovecot/dovecot.conf."

    with tarfile.open("/home/user/mail_data.tar", "r:*") as archive:
        expected = {
            "postfix/main.cf": b"smtpd_banner = $myhostname ESMTP\n",
            "dovecot/dovecot.conf": b"listen = *\n",
        }
        members = {m.name.lstrip("./"): m for m in archive.getmembers() if m.isfile()}
        for name, content in expected.items():
            assert name in members, f"{name} is missing from mail_data.tar."
            assert archive.extractfile(members[name]).read() == content, f"Unexpected content in archived {name}."
            with open("/home/user/mail_data/" + name, "rb") as extracted:
                assert extracted.read() == content, f"Unexpected content in extracted {name}."


def test_c_program_compiled():
    assert os.path.isfile("/home/user/reconstruct.c"), "C program source /home/user/reconstruct.c does not exist."
    assert os.path.isfile("/home/user/reconstruct"), "Compiled C program /home/user/reconstruct does not exist."
    assert os.access("/home/user/reconstruct", os.X_OK), "/home/user/reconstruct is not executable."
    with open("/home/user/reconstruct", "rb") as executable:
        assert executable.read(4) == b"\x7fELF", "/home/user/reconstruct is not a compiled ELF executable."


def test_links_and_directories():
    assert os.path.isdir("/home/user/live_mail"), "/home/user/live_mail directory does not exist."
    assert os.path.islink("/home/user/live_mail/postfix"), "/home/user/live_mail/postfix is not a symlink."
    assert os.path.islink("/home/user/live_mail/dovecot"), "/home/user/live_mail/dovecot is not a symlink."


def test_symlink_targets():
    target_postfix = os.readlink("/home/user/live_mail/postfix")
    target_dovecot = os.readlink("/home/user/live_mail/dovecot")
    assert target_postfix == "/home/user/mail_data/postfix", f"Symlink for postfix points to {target_postfix}, expected /home/user/mail_data/postfix."
    assert target_dovecot == "/home/user/mail_data/dovecot", f"Symlink for dovecot points to {target_dovecot}, expected /home/user/mail_data/dovecot."


def test_acls():
    postfix_acl = subprocess.run(["getfacl", "/home/user/mail_data/postfix"], capture_output=True, text=True).stdout
    main_cf_acl = subprocess.run(["getfacl", "/home/user/mail_data/postfix/main.cf"], capture_output=True, text=True).stdout

    assert "user:nobody:r-x" in postfix_acl, "ACL for nobody on /home/user/mail_data/postfix is not 'r-x'."
    assert "user:nobody:r--" in main_cf_acl, "ACL for nobody on /home/user/mail_data/postfix/main.cf is not 'r--'."


def test_expect_script_really_automates_fetcher():
    script = open("/home/user/fetch.exp", encoding="utf-8", errors="replace").read()
    assert re.search(r"(?m)^\s*spawn(?:\s+--)?\s+", script), "Expect script does not use spawn."
    assert re.search(r"(?m)^\s*expect(?:\s|$)", script), "Expect script does not wait for the password prompt."
    assert re.search(r"(?m)^\s*send(?:\s|$)", script), "Expect script does not send the password."
    assert "Password for backup server: " in script, "Expect script does not contain the required prompt."
    assert "SecureRest0re!" in script, "Expect script does not provide the required password."

    token = uuid.uuid4().hex
    fetcher = "/home/user/fetch_backup"
    tarball = "/home/user/mail_data.tar"
    backup_fetcher = "/tmp/fetch_backup.original"
    backup_tarball = "/tmp/mail_data.tar.original"
    had_tarball = os.path.exists(tarball)

    shutil.copy2(fetcher, backup_fetcher)
    if had_tarball:
        shutil.copy2(tarball, backup_tarball)

    wrapper = f'''#!/usr/bin/python3
import io
import sys
import tarfile
sys.stdout.write("Password for backup server: ")
sys.stdout.flush()
password = sys.stdin.readline().rstrip("\\r\\n")
if password != "SecureRest0re!":
    sys.exit(1)
files = {{
    "postfix/main.cf": b"smtpd_banner = $myhostname ESMTP\\n",
    "dovecot/dovecot.conf": b"listen = *\\n",
    "verification-token": b"{token}",
}}
with tarfile.open("/home/user/mail_data.tar", "w") as archive:
    for name, data in files.items():
        info = tarfile.TarInfo(name)
        info.size = len(data)
        archive.addfile(info, io.BytesIO(data))
'''

    try:
        with open(fetcher, "w", encoding="utf-8") as f:
            f.write(wrapper)
        os.chmod(fetcher, 0o755)
        os.chown(fetcher, 0, 0)
        if os.path.lexists(tarball):
            os.unlink(tarball)

        result = run_as_user(["expect", "/home/user/fetch.exp"], timeout=10)
        assert result.returncode == 0, f"Expect script failed against an interactive fetcher: {result.stdout}{result.stderr}"
        assert os.path.isfile(tarball), "Running the Expect script did not produce mail_data.tar."
        with tarfile.open(tarball, "r:*") as archive:
            assert archive.extractfile("verification-token").read() == token.encode(), "The tarball was not produced by the prompted fetcher."
    finally:
        shutil.copy2(backup_fetcher, fetcher)
        os.chmod(fetcher, 0o755)
        if had_tarball:
            shutil.copy2(backup_tarball, tarball)
        elif os.path.lexists(tarball):
            os.unlink(tarball)


def reset_reconstruction_state():
    if os.path.lexists("/home/user/live_mail"):
        if os.path.islink("/home/user/live_mail"):
            os.unlink("/home/user/live_mail")
        else:
            shutil.rmtree("/home/user/live_mail")
    subprocess.run(["setfacl", "-x", "u:nobody", "/home/user/mail_data/postfix"], check=False, capture_output=True)
    subprocess.run(["setfacl", "-x", "u:nobody", "/home/user/mail_data/postfix/main.cf"], check=False, capture_output=True)


def assert_reconstructed_state():
    assert os.path.isdir("/home/user/live_mail"), "Executing reconstruct did not create live_mail."
    assert stat.S_IMODE(os.stat("/home/user/live_mail").st_mode) == 0o755, "live_mail was not created with mode 0755."
    assert os.path.islink("/home/user/live_mail/postfix")
    assert os.readlink("/home/user/live_mail/postfix") == "/home/user/mail_data/postfix"
    assert os.path.islink("/home/user/live_mail/dovecot")
    assert os.readlink("/home/user/live_mail/dovecot") == "/home/user/mail_data/dovecot"

    postfix_acl = subprocess.run(["getfacl", "-cp", "/home/user/mail_data/postfix"], check=True, capture_output=True, text=True).stdout.splitlines()
    main_acl = subprocess.run(["getfacl", "-cp", "/home/user/mail_data/postfix/main.cf"], check=True, capture_output=True, text=True).stdout.splitlines()
    assert "user:nobody:r-x" in postfix_acl, "Directory ACL is not exactly r-x for nobody."
    assert "user:nobody:r--" in main_acl, "main.cf ACL is not exactly r-- for nobody."


def test_reconstruct_executable_and_source_perform_required_operations():
    reset_reconstruction_state()
    submitted = run_as_user(["/home/user/reconstruct"])
    assert submitted.returncode == 0, f"Submitted reconstruct executable failed: {submitted.stdout}{submitted.stderr}"
    assert_reconstructed_state()

    work = tempfile.mkdtemp(prefix="verify-reconstruct-", dir="/tmp")
    os.chown(work, USER_UID, USER_GID)
    wrapper_c = os.path.join(work, "wrap.c")
    instrumented = os.path.join(work, "reconstruct.instrumented")
    call_log = os.path.join(work, "calls.log")
    with open(call_log, "w"):
        pass
    os.chown(call_log, USER_UID, USER_GID)

    wrapper_source = r'''
#include <stdio.h>
#include <stdlib.h>
#include <sys/stat.h>
#include <unistd.h>

int __real_mkdir(const char *, mode_t);
int __real_symlink(const char *, const char *);
int __real_system(const char *);

static void log_line(const char *kind, const char *a, const char *b) {
    const char *path = getenv("CALL_LOG");
    FILE *f = path ? fopen(path, "a") : NULL;
    if (f) { fprintf(f, "%s|%s|%s\n", kind, a ? a : "", b ? b : ""); fclose(f); }
}
int __wrap_mkdir(const char *path, mode_t mode) {
    char value[32]; snprintf(value, sizeof(value), "%o", (unsigned)mode);
    log_line("mkdir", path, value);
    return __real_mkdir(path, mode);
}
int __wrap_symlink(const char *target, const char *linkpath) {
    log_line("symlink", target, linkpath);
    return __real_symlink(target, linkpath);
}
int __wrap_system(const char *command) {
    log_line("system", command, "");
    return __real_system(command);
}
'''
    with open(wrapper_c, "w") as f:
        f.write(wrapper_source)
    os.chown(wrapper_c, USER_UID, USER_GID)

    compile_result = run_as_user([
        "gcc", "/home/user/reconstruct.c", wrapper_c,
        "-Wl,--wrap=mkdir", "-Wl,--wrap=symlink", "-Wl,--wrap=system",
        "-o", instrumented,
    ])
    assert compile_result.returncode == 0, f"reconstruct.c does not compile: {compile_result.stdout}{compile_result.stderr}"

    reset_reconstruction_state()
    env = os.environ.copy()
    env["CALL_LOG"] = call_log
    source_run = run_as_user([instrumented], env=env)
    assert source_run.returncode == 0, f"Program compiled from reconstruct.c failed: {source_run.stdout}{source_run.stderr}"
    assert_reconstructed_state()

    calls = open(call_log, encoding="utf-8", errors="replace").read().splitlines()
    assert "mkdir|/home/user/live_mail|755" in calls, "reconstruct.c did not call POSIX mkdir() with /home/user/live_mail and mode 0755."
    assert "symlink|/home/user/mail_data/postfix|/home/user/live_mail/postfix" in calls, "reconstruct.c did not call POSIX symlink() for postfix."
    assert "symlink|/home/user/mail_data/dovecot|/home/user/live_mail/dovecot" in calls, "reconstruct.c did not call POSIX symlink() for dovecot."
    system_commands = "\n".join(line[len("system|"):] for line in calls if line.startswith("system|"))
    assert "setfacl" in system_commands, "reconstruct.c did not execute setfacl through system()."
    assert "/home/user/mail_data/postfix" in system_commands and "nobody" in system_commands, "ACL shell commands did not address the postfix paths and nobody user."
    assert "/home/user/mail_data/postfix/main.cf" in system_commands, "ACL shell commands did not address main.cf."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
