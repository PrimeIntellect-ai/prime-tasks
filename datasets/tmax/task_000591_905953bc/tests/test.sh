#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'PY_EOF' > /tmp/test_final_state.py
import os
import shutil
import stat
import subprocess
import uuid

AUDIT_SCRIPT = "/home/user/audit.sh"
AUDIT_REPORT = "/home/user/audit_report.csv"
WEBAPP = "/home/user/webapp"

EXPECTED_REPORT_LINES = [
    "/home/user/webapp/config.php,Injection_Risk",
    "/home/user/webapp/config.php,World_Writable",
    "/home/user/webapp/data.txt,World_Writable",
    "/home/user/webapp/index.html,CSP_XSS_Risk",
]


def write_file(path, content, mode=0o644):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        f.write(content)
    os.chmod(path, mode)


def reset_webapp(files):
    shutil.rmtree(WEBAPP, ignore_errors=True)
    os.makedirs(WEBAPP, mode=0o755)
    os.chmod(WEBAPP, 0o755)
    for relative_path, content, mode in files:
        write_file(os.path.join(WEBAPP, relative_path), content, mode)


def expected_report():
    findings = []
    for root, dirs, files in os.walk(WEBAPP):
        dirs.sort()
        files.sort()
        for name in files:
            path = os.path.abspath(os.path.join(root, name))
            mode = os.stat(path).st_mode
            with open(path, "r", encoding="utf-8", errors="replace") as f:
                content = f.read()

            if mode & stat.S_IWOTH:
                findings.append(f"{path},World_Writable")
            if name.endswith((".html", ".js")):
                if "<script" in content and "nonce=" not in content and "integrity=" not in content:
                    findings.append(f"{path},CSP_XSS_Risk")
            if name.endswith(".php") and "eval(" in content:
                findings.append(f"{path},Injection_Risk")
    return sorted(findings)


def run_and_read_report():
    if os.path.lexists(AUDIT_REPORT):
        os.remove(AUDIT_REPORT)

    result = subprocess.run(
        ["/bin/bash", AUDIT_SCRIPT],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=15,
    )
    assert result.returncode == 0, (
        f"Audit script failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.isfile(AUDIT_REPORT), f"Audit report {AUDIT_REPORT} does not exist."
    with open(AUDIT_REPORT, "r", encoding="utf-8") as f:
        return [line.strip() for line in f if line.strip()]


def main():
    # Preserve the original existence assertions, including the requirement that
    # the agent ran the script once before verification.
    assert os.path.isfile(AUDIT_SCRIPT), f"Audit script {AUDIT_SCRIPT} does not exist."
    assert os.path.isfile(AUDIT_REPORT), f"Audit report {AUDIT_REPORT} does not exist."

    syntax = subprocess.run(
        ["/bin/bash", "-n", AUDIT_SCRIPT],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
    )
    assert syntax.returncode == 0, f"audit.sh is not valid Bash: {syntax.stderr}"

    # Restore the intended fixture modes. The image setup accidentally made every
    # file world-writable with chmod -R 777.
    baseline = [
        ("index.html", '<html>\n<body>\n<script src="app.js"></script>\n</body>\n</html>\n', 0o644),
        ("safe.html", '<html>\n<body>\n<script nonce="rAnd0m" src="app.js"></script>\n</body>\n</html>\n', 0o644),
        ("config.php", "<?php\n$cmd = $_GET['cmd'];\neval($cmd);\n?>\n", 0o777),
        ("data.txt", "user data\n", 0o666),
        ("app.js", 'console.log("Hello, world!");\n', 0o644),
    ]
    reset_webapp(baseline)
    assert expected_report() == EXPECTED_REPORT_LINES
    lines = run_and_read_report()
    assert lines == EXPECTED_REPORT_LINES, (
        f"Audit report contents are incorrect.\nExpected:\n{EXPECTED_REPORT_LINES}\nActual:\n{lines}"
    )

    # Exercise the submitted script against unpredictable names, nested paths,
    # safe cases, each individual finding, and files with multiple findings.
    for _ in range(2):
        token = uuid.uuid4().hex
        nested = f"nested_{uuid.uuid4().hex}"
        cases = [
            (f"unsafe_{token}.html", "<html><script src='x.js'></script></html>\n", 0o644),
            (f"safe_nonce_{token}.html", "<script nonce='abc' src='x.js'></script>\n", 0o644),
            (f"{nested}/unsafe_{token}.js", 'const marker = "<script";\n', 0o644),
            (f"{nested}/safe_integrity_{token}.js", '<script integrity="sha256-x">\n', 0o644),
            (f"inject_{token}.php", "<?php eval($value); ?>\n", 0o644),
            (f"case_safe_{token}.php", "<?php EVAL($value); ?>\n", 0o644),
            (f"writable_{token}.txt", "ordinary data\n", 0o666),
            (f"{nested}/multi_{token}.php", "<?php eval($value); ?>\n", 0o606),
            (f"multi_{token}.html", "<script src='x.js'></script>\n", 0o602),
            (f"plain_{token}.txt", "eval( <script\n", 0o644),
        ]
        reset_webapp(cases)
        expected = expected_report()
        actual = run_and_read_report()
        assert actual == expected, (
            f"Audit script failed a generated scan.\nExpected:\n{expected}\nActual:\n{actual}"
        )


if __name__ == "__main__":
    main()
PY_EOF

if python3 /tmp/test_final_state.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
