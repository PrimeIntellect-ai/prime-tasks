Crash when streaming event with non-UTF-8 data
**What happened (please include outputs or screenshots)**:
```
72 [00000]   File "/root/.pyenv/versions/3.10.11/lib/python3.10/site-packages/kubernetes/watch/watch.py", line 165, in stream
72 [00000]     for line in iter_resp_lines(resp):
72 [00000]   File "/root/.pyenv/versions/3.10.11/lib/python3.10/site-packages/kubernetes/watch/watch.py", line 58, in iter_resp_lines
72 [00000]     seg = seg.decode('utf8')
72 [00000] UnicodeDecodeError: 'utf-8' codec can't decode bytes in position 2046-2047: unexpected end of data
```

**What you expected to happen**:
If there's invalid data in an event, it should at least be _possible_ to discard that data or event and continue. I'm not sure what the default behavior should be; it's possible that something which is currently `str` should be `bytes`, or that we should use the unicode replacement character �, or something else.

**How to reproduce it (as minimally and precisely as possible)**:
I'm afraid I don't currently have a minimal reproducer with real Kubernetes but it should be possible to reproduce with a test by adding a `bytes` object with invalid UTF-8 to https://github.com/kubernetes-client/python/blob/dbe83efe0a631a591a0a5a3fc883ef0e646a293a/kubernetes/watch/watch_test.py#L38-L39

**Anything else we need to know?**:
I suspect this is the same issue as https://github.com/kubernetes-client/python-base/issues/245

**Environment**:
- Kubernetes version (`kubectl version`): 1.23
- OS (e.g., MacOS 10.13.6): Linux
- Python version (`python --version`): 3.10.10
- Python client version (`pip list | grep kubernetes`): 26.1.0

### Additional contract requirements

- Replace each invalid UTF-8 byte in watch stream data with one `�` character, while preserving valid UTF-8 content and continuing to process subsequent events.
