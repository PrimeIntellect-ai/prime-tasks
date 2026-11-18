#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'PY_EOF' > /tmp/verify_task.py
import glob
import json
import os
import signal
import subprocess
import sys
import time
from pathlib import Path

import grpc
from google.protobuf import descriptor_pb2, descriptor_pool, message_factory

AUDIO = "/app/etl_spikes.wav"
OUTPUT = "/home/user/processed_logs.json"
HOST_HEX = "0100007F"
PORT_HEX = format(50051, "04X")


def listening_inodes():
    found = set()
    exact = False
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            lines = Path(table).read_text().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            cols = line.split()
            local, state, inode = cols[1], cols[3], cols[9]
            address, port = local.split(":")
            if state != "0A" or port.upper() != PORT_HEX:
                continue
            found.add(inode)
            # IPv4 loopback, or its IPv4-mapped IPv6 representation.
            if address.upper() == HOST_HEX or address.upper().endswith("FFFF0000" + HOST_HEX):
                exact = True
    return found, exact


def pids_for_inodes(inodes):
    result = set()
    for proc in glob.glob("/proc/[0-9]*"):
        pid = int(proc.rsplit("/", 1)[1])
        for fd in glob.glob(proc + "/fd/*"):
            try:
                target = os.readlink(fd)
            except OSError:
                continue
            if target.startswith("socket:[") and target[8:-1] in inodes:
                result.add(pid)
                break
    return result


def listener_info():
    inodes, exact = listening_inodes()
    pids = pids_for_inodes(inodes)
    assert pids, "No server is listening on 127.0.0.1:50051."
    pid = min(pids)
    cmd = Path(f"/proc/{pid}/cmdline").read_bytes().split(b"\0")
    cmd = [x.decode(errors="surrogateescape") for x in cmd if x]
    assert cmd and "python" in os.path.basename(cmd[0]).lower(), "The listener is not the required Python server."
    cwd = os.readlink(f"/proc/{pid}/cwd")
    assert exact, "The service must bind specifically to 127.0.0.1:50051, not a wildcard address."
    return pid, cmd, cwd


def kill_pid(pid):
    try:
        os.kill(pid, signal.SIGTERM)
    except ProcessLookupError:
        return
    for _ in range(30):
        if not os.path.exists(f"/proc/{pid}"):
            return
        time.sleep(0.1)
    try:
        os.kill(pid, signal.SIGKILL)
    except ProcessLookupError:
        pass


def kill_port_listeners():
    inodes, _ = listening_inodes()
    for pid in pids_for_inodes(inodes):
        kill_pid(pid)


def stop_process(proc):
    if proc is None or proc.poll() is not None:
        return
    try:
        os.killpg(proc.pid, signal.SIGTERM)
    except ProcessLookupError:
        return
    try:
        proc.wait(timeout=3)
    except subprocess.TimeoutExpired:
        try:
            os.killpg(proc.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass


def start_command(cmd, cwd):
    return subprocess.Popen(
        cmd, cwd=cwd, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL, start_new_session=True
    )


def find_pipeline():
    candidates = []
    saw_audio_source = False
    for root in ("/home/user", "/app"):
        for path in Path(root).rglob("*.py"):
            if path.name.endswith(("_pb2.py", "_pb2_grpc.py")):
                continue
            try:
                text = path.read_text(errors="ignore")
            except OSError:
                continue
            if AUDIO in text or "etl_spikes.wav" in text:
                saw_audio_source = True
            if OUTPUT in text or "processed_logs.json" in text:
                score = int(AUDIO in text or "etl_spikes.wav" in text)
                candidates.append((score, path))
    assert saw_audio_source, "No Python audio-extraction artifact references etl_spikes.wav."
    assert candidates, "No executable Python transformation pipeline was found."
    candidates.sort(key=lambda x: (x[0], str(x[1])), reverse=True)
    return candidates[0][1]


def find_and_compile_proto():
    protos = list(Path("/home/user").rglob("*.proto")) + list(Path("/app").rglob("*.proto"))
    assert protos, "No protobuf definition was created."
    selected = None
    for proto in protos:
        text = proto.read_text(errors="ignore")
        if "service LogAuditor" in text and "GetRecord" in text:
            selected = proto
            break
    assert selected is not None, "No proto defines LogAuditor.GetRecord."

    stem = selected.stem
    generated = list(selected.parent.glob(stem + "*_pb2.py"))
    generated_grpc = list(selected.parent.glob(stem + "*_pb2_grpc.py"))
    assert generated and generated_grpc, "The protobuf definitions were not compiled into Python modules."

    descriptor_file = "/tmp/submission.desc"
    import grpc_tools
    include = str(Path(grpc_tools.__file__).parent / "_proto")
    result = subprocess.run([
        sys.executable, "-m", "grpc_tools.protoc",
        "-I" + str(selected.parent), "-I" + include,
        "--include_imports", "--descriptor_set_out=" + descriptor_file,
        selected.name,
    ], cwd=str(selected.parent), stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    assert result.returncode == 0, "Submitted protobuf does not compile: " + result.stderr

    fds = descriptor_pb2.FileDescriptorSet()
    fds.ParseFromString(Path(descriptor_file).read_bytes())
    pool = descriptor_pool.DescriptorPool()
    pending = list(fds.file)
    while pending:
        progressed = False
        for fd in pending[:]:
            try:
                pool.Add(fd)
            except Exception:
                continue
            pending.remove(fd)
            progressed = True
        assert progressed, "Could not load the submitted protobuf descriptors."

    service = None
    for fd in fds.file:
        for item in fd.service:
            if item.name == "LogAuditor":
                full_name = (fd.package + "." if fd.package else "") + item.name
                service = pool.FindServiceByName(full_name)
                break
    assert service is not None, "Service must be named LogAuditor."
    methods = [m for m in service.methods if m.name == "GetRecord"]
    assert len(methods) == 1, "LogAuditor must define GetRecord exactly once."
    method = methods[0]
    req_fields = {f.name: f for f in method.input_type.fields}
    resp_fields = {f.name: f for f in method.output_type.fields}
    assert set(req_fields) == {"record_id"}, "RecordRequest must contain the record_id field."
    assert set(resp_fields) == {"timestamp", "status", "lang"}, "RecordResponse must contain timestamp, status, and lang."
    for field in list(req_fields.values()) + list(resp_fields.values()):
        assert field.type == field.TYPE_STRING, "All request and response fields must be strings."
    return service, method


def check_json():
    assert os.path.exists(OUTPUT), f"Processed logs JSON file {OUTPUT} is missing."
    try:
        with open(OUTPUT, "r", encoding="utf-8") as f:
            data = json.load(f)
    except json.JSONDecodeError:
        raise AssertionError(f"File {OUTPUT} contains invalid JSON.")
    assert isinstance(data, list), "JSON root should be an array."
    assert len(data) == 2, "JSON must contain exactly the two deduplicated records."
    assert all(isinstance(item, dict) for item in data), "Every JSON entry must be an object."
    required = {"lang", "timestamp", "record_id", "status"}
    assert all(set(item) == required for item in data), "Each record must contain exactly the required fields."
    assert all(all(isinstance(item[k], str) for k in required) for item in data), "All record fields must be strings."
    assert len({item["record_id"] for item in data}) == len(data), "Record IDs were not deduplicated."

    xyz_record = next((item for item in data if item.get("record_id") == "XYZ-123"), None)
    assert xyz_record is not None, "Record XYZ-123 is missing from the processed JSON."
    assert xyz_record.get("lang") == "EN", "Record XYZ-123 should have lang 'EN' (earliest timestamp)."
    assert xyz_record.get("timestamp") == "2023-10-01T10:00:00Z", "Record XYZ-123 has incorrect timestamp."
    assert xyz_record.get("status") == "FAILED", "Record XYZ-123 has incorrect status."

    abc_record = next((item for item in data if item.get("record_id") == "ABC-999"), None)
    assert abc_record is not None, "Record ABC-999 is missing from the processed JSON."
    assert abc_record.get("lang") == "ZH", "Record ABC-999 should have lang 'ZH'."
    assert abc_record.get("timestamp") == "2023-10-01T10:10:00Z", "Record ABC-999 has incorrect timestamp."
    assert abc_record.get("status") == "SUCCESS", "Record ABC-999 has incorrect status."


def check_grpc(service, method):
    _, exact = listening_inodes()
    assert exact, "gRPC server is not listening specifically on 127.0.0.1:50051."
    Request = message_factory.GetMessageClass(method.input_type)
    Response = message_factory.GetMessageClass(method.output_type)
    rpc_path = f"/{service.full_name}/{method.name}"
    channel = grpc.insecure_channel("127.0.0.1:50051")
    grpc.channel_ready_future(channel).result(timeout=5)
    call = channel.unary_unary(
        rpc_path,
        request_serializer=lambda message: message.SerializeToString(),
        response_deserializer=Response.FromString,
    )
    xyz = call(Request(record_id="XYZ-123"), timeout=5)
    assert xyz.timestamp == "2023-10-01T10:00:00Z"
    assert xyz.status == "FAILED"
    assert xyz.lang == "EN"
    abc = call(Request(record_id="ABC-999"), timeout=5)
    assert abc.timestamp == "2023-10-01T10:10:00Z"
    assert abc.status == "SUCCESS"
    assert abc.lang == "ZH"
    missing = call(Request(record_id="DOES-NOT-EXIST"), timeout=5)
    assert missing.timestamp == "" and missing.status == "" and missing.lang == "", "Unknown IDs must return an empty response."
    channel.close()


def main():
    assert os.path.isfile(AUDIO), "The supplied audio artifact is missing."
    service, method = find_and_compile_proto()
    original_pid, server_cmd, server_cwd = listener_info()
    pipeline = find_pipeline()
    pipeline_cmd = [sys.executable, str(pipeline)]

    kill_pid(original_pid)
    kill_port_listeners()

    backup = AUDIO + ".verifier-backup"
    missing_proc = None
    live_proc = None
    server_proc = None
    try:
        if os.path.exists(OUTPUT):
            os.remove(OUTPUT)
        os.rename(AUDIO, backup)
        missing_proc = start_command(pipeline_cmd, str(pipeline.parent))
        time.sleep(5)
        assert not os.path.exists(OUTPUT), "The alleged pipeline generated the fixed answer without reading the required audio artifact."
        stop_process(missing_proc)
        missing_proc = None
        kill_port_listeners()
        os.rename(backup, AUDIO)

        start_ns = time.time_ns()
        live_proc = start_command(pipeline_cmd, str(pipeline.parent))
        deadline = time.time() + 45
        while time.time() < deadline:
            if os.path.exists(OUTPUT) and os.stat(OUTPUT).st_mtime_ns >= start_ns:
                break
            time.sleep(0.25)
        assert os.path.exists(OUTPUT) and os.stat(OUTPUT).st_mtime_ns >= start_ns, "Executing the submitted pipeline did not regenerate processed_logs.json from the audio."
        check_json()

        inodes, _ = listening_inodes()
        if not inodes:
            server_proc = start_command(server_cmd, server_cwd)
        deadline = time.time() + 20
        while time.time() < deadline and not listening_inodes()[0]:
            time.sleep(0.2)
        check_grpc(service, method)
        # Leave the successfully verified service running.
    finally:
        if os.path.exists(backup):
            if os.path.exists(AUDIO):
                os.remove(AUDIO)
            os.rename(backup, AUDIO)


if __name__ == "__main__":
    main()
PY_EOF

if python3 /tmp/verify_task.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
