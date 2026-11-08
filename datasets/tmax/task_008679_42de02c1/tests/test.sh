#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import os
import secrets
import stat
import subprocess
import textwrap

HOME = "/home/user"
SOURCE = f"{HOME}/recover.c"
RECOVER = f"{HOME}/recover"
AUDIT = f"{HOME}/audit.log"
SERVICE = f"{HOME}/vuln_service"
OUTPUT = f"{HOME}/recovered_flag.txt"


def run(cmd, **kwargs):
    return subprocess.run(cmd, check=True, text=True, capture_output=True, **kwargs)


def test_recover_source_code_exists():
    assert os.path.exists(SOURCE), f"Missing C source file: {SOURCE}"
    assert os.path.isfile(SOURCE), f"Expected a file, but got something else: {SOURCE}"
    with open(SOURCE, "r") as f:
        content = f.read()
    assert len(content) > 0, f"The source file {SOURCE} is empty"


def test_recover_executable_exists():
    assert os.path.exists(RECOVER), f"Missing compiled executable: {RECOVER}"
    assert os.path.isfile(RECOVER), f"Expected a file, but got something else: {RECOVER}"
    assert os.access(RECOVER, os.X_OK), f"File is not executable: {RECOVER}"


def install_test_service():
    nonce = secrets.token_hex(12)
    config = f"/root/.recover_verifier_{nonce}"
    leaker = f"/tmp/recover_leaker_{nonce}"
    service_src = f"/tmp/vuln_service_{nonce}.c"
    leaker_src = f"/tmp/recover_leaker_{nonce}.c"

    with open(leaker_src, "w") as f:
        f.write(textwrap.dedent(r'''
            #include <time.h>
            int main(void) {
                struct timespec ts = {0, 500000000L};
                nanosleep(&ts, 0);
                return 0;
            }
        '''))
    run(["gcc", "-O2", "-o", leaker, leaker_src])
    os.chmod(leaker, 0o755)

    with open(service_src, "w") as f:
        f.write(textwrap.dedent(f'''
            #include <stdio.h>
            #include <stdlib.h>
            #include <string.h>
            #include <unistd.h>

            int main(int argc, char **argv) {{
                char trigger[256], flag[256];
                FILE *fp;
                pid_t pid;
                if (argc < 2) return 1;
                fp = fopen("{config}", "r");
                if (!fp) return 2;
                if (!fgets(trigger, sizeof(trigger), fp) ||
                    !fgets(flag, sizeof(flag), fp)) {{
                    fclose(fp);
                    return 3;
                }}
                fclose(fp);
                trigger[strcspn(trigger, "\\r\\n")] = 0;
                flag[strcspn(flag, "\\r\\n")] = 0;
                if (strcmp(argv[1], trigger) != 0) return 0;

                /* Drop the setuid privilege after reading the verifier-only
                   secret so the transient process is visible to the user. */
                if (setuid(getuid()) != 0) return 4;
                pid = fork();
                if (pid < 0) return 5;
                if (pid == 0) {{
                    execl("{leaker}", "sleep", "0.5", flag, (char *)0);
                    _exit(127);
                }}
                return 0;
            }}
        '''))

    run(["gcc", "-O2", "-o", SERVICE, service_src])
    os.chown(SERVICE, 0, 0)
    os.chmod(SERVICE, stat.S_ISUID | 0o755)
    return config


def write_case(config, payload, flag):
    with open(config, "w") as f:
        f.write(payload + "\n" + flag + "\n")
    os.chown(config, 0, 0)
    os.chmod(config, 0o600)

    encoded = base64.b64encode(payload.encode()).decode()
    audit = (
        "[2023-10-25 14:22:01] INFO Connection established from 192.168.1.105\n"
        "[2023-10-25 14:22:05] WARNING Suspicious input detected on port 8080\n"
        f"[2023-10-25 14:22:06] ALERT Trigger sequence captured. Payload (Base64): {encoded}\n"
        "[2023-10-25 14:22:06] INFO Connection closed.\n"
    )
    with open(AUDIT, "w") as f:
        f.write(audit)
    os.chmod(AUDIT, 0o644)


def execute_and_check(expected_flag):
    try:
        os.unlink(OUTPUT)
    except FileNotFoundError:
        pass

    proc = subprocess.run(
        ["runuser", "-u", "user", "--", RECOVER],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
    )
    assert proc.returncode == 0, (
        f"Recovery executable failed with status {proc.returncode}: {proc.stderr}"
    )

    assert os.path.exists(OUTPUT), f"Missing file: {OUTPUT}"
    assert os.path.isfile(OUTPUT), f"Expected a file, but got something else: {OUTPUT}"
    with open(OUTPUT, "r") as f:
        content = f.read().strip()
    assert content == expected_flag, (
        f"Expected flag '{expected_flag}', but found '{content}' in {OUTPUT}"
    )
    with open(OUTPUT, "rb") as f:
        assert f.read() == expected_flag.encode(), (
            f"{OUTPUT} must contain only the extracted flag"
        )


def test_recovered_flag():
    # Recompile the submitted C source so the exercised executable must be the
    # submitted C implementation rather than an unrelated executable file.
    run(["gcc", "-O2", "-o", RECOVER, SOURCE])
    os.chmod(RECOVER, 0o755)

    config = install_test_service()
    try:
        # Preserve the original exact expected-flag assertion, but obtain it by
        # actually executing the submitted recovery tool.
        write_case(config, "AlphaBravoCharlie99!", "FLAG{pr0c_cmdl1n3_l34k_m4st3r}")
        execute_and_check("FLAG{pr0c_cmdl1n3_l34k_m4st3r}")

        # A fresh, unpredictable case rejects hardcoded payloads and flags.
        payload = "Trigger" + secrets.token_hex(16) + "!"
        flag = "FLAG{" + secrets.token_hex(20) + "}"
        write_case(config, payload, flag)
        execute_and_check(flag)
    finally:
        try:
            os.unlink(config)
        except FileNotFoundError:
            pass
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
