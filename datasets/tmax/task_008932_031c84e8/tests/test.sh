#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import pwd
import re
import subprocess
import tempfile


def run_with_stubs(script_path, command_names):
    with tempfile.TemporaryDirectory(prefix="verify-script-") as td:
        os.chmod(td, 0o755)
        log_path = os.path.join(td, "calls.jsonl")
        open(log_path, "w").close()
        os.chmod(log_path, 0o666)

        logger_path = os.path.join(td, "logger.py")
        with open(logger_path, "w") as f:
            f.write(
                "import json, sys\n"
                f"with open({log_path!r}, 'a') as out:\n"
                "    out.write(json.dumps(sys.argv[1:]) + '\\n')\n"
            )
        os.chmod(logger_path, 0o755)

        for name in command_names:
            wrapper = os.path.join(td, name)
            with open(wrapper, "w") as f:
                f.write(f"#!/bin/sh\nexec /usr/bin/python3 {logger_path} {name} \"$@\"\n")
            os.chmod(wrapper, 0o755)

        sudo_wrapper = os.path.join(td, "sudo")
        with open(sudo_wrapper, "w") as f:
            f.write("#!/bin/sh\nexec \"$@\"\n")
        os.chmod(sudo_wrapper, 0o755)

        nobody = pwd.getpwnam("nobody")

        def demote():
            os.setgroups([])
            os.setgid(nobody.pw_gid)
            os.setuid(nobody.pw_uid)

        result = subprocess.run(
            ["/bin/bash", "--noprofile", "--norc", script_path],
            cwd=td,
            env={"PATH": td + ":/usr/bin:/bin", "HOME": td, "LC_ALL": "C"},
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=10,
            preexec_fn=demote,
        )
        assert result.returncode == 0, (
            f"{script_path} failed when executed with safe command stubs: "
            f"{result.stderr}"
        )

        with open(log_path) as f:
            return [json.loads(line) for line in f if line.strip()]


def has_option(args, option, value):
    return any(args[i] == option and args[i + 1] == value for i in range(len(args) - 1))


def test_phase1_directory_structure_and_links():
    base_dir = "/home/user/deploy_pkg/app"

    for d in ['bin', 'logs', 'data', 'conf']:
        dir_path = os.path.join(base_dir, d)
        assert os.path.isdir(dir_path), f"Directory {dir_path} does not exist."

    symlink_path = os.path.join(base_dir, 'current')
    assert os.path.islink(symlink_path), f"{symlink_path} is not a symbolic link."

    target = os.readlink(symlink_path)
    assert target == "bin", f"Symlink points to '{target}' instead of 'bin'."


def test_phase2_identity_script():
    script_path = "/home/user/deploy_pkg/create_identities.sh"
    assert os.path.isfile(script_path), f"Script {script_path} does not exist."

    with open(script_path, 'r') as f:
        content = f.read()

    assert re.search(r'groupadd\s+.*-g\s+2000\s+dataproc', content) or \
           re.search(r'groupadd\s+dataproc\s+.*-g\s+2000', content), \
           "Missing or incorrect groupadd command for dataproc (GID 2000)."

    assert re.search(r'useradd\s+.*-u\s+2001\s+.*-g\s+(2000|dataproc)\s+data_ingest', content) or \
           re.search(r'useradd\s+.*-g\s+(2000|dataproc)\s+.*-u\s+2001\s+data_ingest', content), \
           "Missing or incorrect useradd command for data_ingest (UID 2001, Group dataproc)."

    assert re.search(r'useradd\s+.*-u\s+2002\s+.*-g\s+(2000|dataproc)\s+data_export', content) or \
           re.search(r'useradd\s+.*-g\s+(2000|dataproc)\s+.*-u\s+2002\s+data_export', content), \
           "Missing or incorrect useradd command for data_export (UID 2002, Group dataproc)."

    subprocess.run(["/bin/bash", "-n", script_path], check=True)
    calls = run_with_stubs(script_path, ["groupadd", "useradd"])

    group_calls = [c[1:] for c in calls if c and c[0] == "groupadd"]
    user_calls = [c[1:] for c in calls if c and c[0] == "useradd"]

    assert any(has_option(args, "-g", "2000") and "dataproc" in args
               for args in group_calls), "The dataproc groupadd command is not executable."
    assert any(has_option(args, "-u", "2001") and
               (has_option(args, "-g", "dataproc") or has_option(args, "-g", "2000")) and
               "data_ingest" in args for args in user_calls), \
           "The data_ingest useradd command is not executable."
    assert any(has_option(args, "-u", "2002") and
               (has_option(args, "-g", "dataproc") or has_option(args, "-g", "2000")) and
               "data_export" in args for args in user_calls), \
           "The data_export useradd command is not executable."


def test_phase3_fstab_append():
    fstab_path = "/home/user/deploy_pkg/fstab.append"
    assert os.path.isfile(fstab_path), f"File {fstab_path} does not exist."

    with open(fstab_path, 'r') as f:
        content = f.read()

    assert re.search(r'/var/log/dataproc\s+/app/logs\s+(none|bind)\s+bind\s+0\s+0', content), \
           "Missing or incorrect fstab entry for bind mount."
    assert re.search(r'10\.0\.0\.5:/export/data\s+/app/data\s+nfs4\s+ro\s+0\s+0', content), \
           "Missing or incorrect fstab entry for NFS mount."

    lines = content.splitlines()
    assert len(lines) == 2, "fstab.append must contain exactly two lines."
    assert re.fullmatch(r'[ \t]*/var/log/dataproc[ \t]+/app/logs[ \t]+(?:none|bind)[ \t]+bind[ \t]+0[ \t]+0[ \t]*', lines[0]), \
           "The first fstab line is not a valid bind-mount entry."
    assert re.fullmatch(r'[ \t]*10\.0\.0\.5:/export/data[ \t]+/app/data[ \t]+nfs4[ \t]+ro[ \t]+0[ \t]+0[ \t]*', lines[1]), \
           "The second fstab line is not a valid read-only NFSv4 entry."


def test_phase4_firewall_script():
    script_path = "/home/user/deploy_pkg/firewall.sh"
    assert os.path.isfile(script_path), f"Script {script_path} does not exist."

    with open(script_path, 'r') as f:
        content = f.read()

    assert re.search(r'iptables\s+-A\s+INPUT\s+.*-p\s+tcp\s+.*--dport\s+8080\s+.*-j\s+ACCEPT', content) or \
           re.search(r'iptables\s+-A\s+INPUT\s+.*--dport\s+8080\s+.*-p\s+tcp\s+.*-j\s+ACCEPT', content), \
           "Missing or incorrect iptables rule to allow incoming TCP port 8080."
    assert re.search(r'iptables\s+-t\s+nat\s+-A\s+PREROUTING\s+.*-p\s+tcp\s+.*--dport\s+80\s+.*-j\s+REDIRECT\s+--to-ports?\s+8080', content), \
           "Missing or incorrect iptables rule to redirect port 80 to 8080."
    assert re.search(r'iptables\s+-A\s+INPUT\s+.*-s\s+192\.168\.1\.100\s+.*-j\s+DROP', content), \
           "Missing or incorrect iptables rule to drop traffic from 192.168.1.100."

    subprocess.run(["/bin/bash", "-n", script_path], check=True)
    calls = run_with_stubs(script_path, ["iptables"])
    rules = [c[1:] for c in calls if c and c[0] == "iptables"]

    assert any(has_option(r, "-A", "INPUT") and has_option(r, "-p", "tcp") and
               has_option(r, "--dport", "8080") and has_option(r, "-j", "ACCEPT")
               for r in rules), "The TCP 8080 ACCEPT rule is not executable."
    assert any(has_option(r, "-t", "nat") and has_option(r, "-A", "PREROUTING") and
               has_option(r, "-p", "tcp") and has_option(r, "--dport", "80") and
               has_option(r, "-j", "REDIRECT") and
               (has_option(r, "--to-port", "8080") or has_option(r, "--to-ports", "8080"))
               for r in rules), "The port 80 redirect rule is not executable."
    assert any(has_option(r, "-A", "INPUT") and has_option(r, "-s", "192.168.1.100") and
               has_option(r, "-j", "DROP") for r in rules), \
           "The source-address DROP rule is not executable."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
