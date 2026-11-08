Crash when using retry
```
Traceback (most recent call last):
  File "/usr/lib/python3.5/concurrent/futures/thread.py", line 55, in run
    result = self.fn(*self.args, **self.kwargs)
  File "scrape_archives.py", line 29, in publish_records
    batch.create_record(record, safe=False)
  File "/usr/lib/python3.5/contextlib.py", line 66, in __exit__
    next(self.gen)
  File "/home/mathieu/Code/Mozilla/buildhub/jobs/.venv3/lib/python3.5/site-packages/kinto_http/__init__.py", line 101, in batch
    batch_session.send()
  File "/home/mathieu/Code/Mozilla/buildhub/jobs/.venv3/lib/python3.5/site-packages/kinto_http/batch.py", line 52, in send
    resp, headers = self.session.request(**kwargs)
  File "/home/mathieu/Code/Mozilla/buildhub/jobs/.venv3/lib/python3.5/site-packages/kinto_http/session.py", line 80, in request
    time.sleep(retry_after)
TypeError: an integer is required (got type str)
```
