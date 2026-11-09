#!/bin/bash
mkdir -p /logs/verifier

USER_UID="$(id -u user)"
RUNTIME_DIR="/run/user/${USER_UID}"
BUS_PATH="${RUNTIME_DIR}/bus"
DROPIN_DIR="${RUNTIME_DIR}/systemd/user/prepare-disk.service.d"
DROPIN_FILE="${DROPIN_DIR}/verifier-failure.conf"

uctl() {
    runuser -u user -- env \
        XDG_RUNTIME_DIR="${RUNTIME_DIR}" \
        DBUS_SESSION_BUS_ADDRESS="unix:path=${BUS_PATH}" \
        systemctl --user "$@"
}

verify_task() {
    local requires after failure_test_ok

    test -S "${BUS_PATH}" || {
        echo "User systemd bus is unavailable." >&2
        return 1
    }

    uctl daemon-reload || return 1

    # Check the effective, systemd-parsed dependency graph rather than trusting
    # substrings that might occur in comments or unrelated sections.
    requires="$(uctl show vm-launcher.service -p Requires --value)" || return 1
    after="$(uctl show vm-launcher.service -p After --value)" || return 1
    case " ${requires} " in
        *" prepare-disk.service "*) ;;
        *) echo "Effective Requires dependency is missing." >&2; return 1 ;;
    esac
    case " ${after} " in
        *" prepare-disk.service "*) ;;
        *) echo "Effective After ordering is missing." >&2; return 1 ;;
    esac

    # Prove the launcher is blocked when its ordered, required preparation job
    # fails. The override is verifier-only and is removed before the real run.
    uctl stop vm-launcher.service prepare-disk.service >/dev/null 2>&1 || true
    uctl reset-failed vm-launcher.service prepare-disk.service >/dev/null 2>&1 || true
    rm -f /home/user/active-disk.qcow2 /home/user/vm_run.log

    mkdir -p "${DROPIN_DIR}" || return 1
    cat > "${DROPIN_FILE}" <<'EOF'
[Service]
ExecStart=
ExecStart=/bin/false
EOF
    chmod 0644 "${DROPIN_FILE}"

    uctl daemon-reload || return 1
    failure_test_ok=1
    if uctl start vm-launcher.service >/dev/null 2>&1; then
        echo "vm-launcher.service started even though its required preparation unit failed." >&2
        failure_test_ok=0
    fi
    if test -e /home/user/vm_run.log; then
        echo "The launcher ran despite failure of its ordered required unit." >&2
        failure_test_ok=0
    fi

    rm -f "${DROPIN_FILE}"
    rmdir "${DROPIN_DIR}" >/dev/null 2>&1 || true
    uctl daemon-reload || return 1
    uctl reset-failed vm-launcher.service prepare-disk.service >/dev/null 2>&1 || true
    test "${failure_test_ok}" -eq 1 || return 1

    # Exercise the submitted unit from a clean state. Neither the symlink nor
    # the success log can be pre-created to satisfy this run.
    uctl stop vm-launcher.service prepare-disk.service >/dev/null 2>&1 || true
    rm -f /home/user/active-disk.qcow2 /home/user/vm_run.log
    uctl start vm-launcher.service || return 1

    test "$(uctl show vm-launcher.service -p Result --value)" = "success" || return 1
    test "$(uctl show prepare-disk.service -p Result --value)" = "success" || return 1

    cat <<'TEST_EOF' > /tmp/test_final_state.py
import os

def test_vm_launcher_service_dependencies():
    path = "/home/user/.config/systemd/user/vm-launcher.service"
    assert os.path.isfile(path), f"Service file {path} does not exist."

    with open(path, "r") as f:
        content = f.read()

    assert "Requires=prepare-disk.service" in content, "vm-launcher.service is missing 'Requires=prepare-disk.service'."
    assert "After=prepare-disk.service" in content, "vm-launcher.service is missing 'After=prepare-disk.service'."

def test_active_disk_symlink_created():
    symlink_path = "/home/user/active-disk.qcow2"
    target_path = "/home/user/storage/base-image.qcow2"

    assert os.path.islink(symlink_path), f"{symlink_path} is not a symlink. Did prepare-disk.service run?"
    assert os.readlink(symlink_path) == target_path, f"{symlink_path} does not point to {target_path}."

def test_vm_run_log_success():
    log_path = "/home/user/vm_run.log"
    assert os.path.isfile(log_path), f"Log file {log_path} does not exist. Did vm-launcher.service run successfully?"

    with open(log_path, "r") as f:
        content = f.read()

    assert "SUCCESS" in content, f"Log file {log_path} does not contain 'SUCCESS'. The script may have failed."
TEST_EOF

    python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1 || return 1
}

if verify_task; then
    echo "1" > /logs/verifier/reward.txt
else
    rm -f "${DROPIN_FILE}"
    rmdir "${DROPIN_DIR}" >/dev/null 2>&1 || true
    uctl daemon-reload >/dev/null 2>&1 || true
    echo "0" > /logs/verifier/reward.txt
fi
