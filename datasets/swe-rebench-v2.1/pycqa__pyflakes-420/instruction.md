Incorrect line number for syntax error in type comment
Minor issue, pyflakes 2.1.0 (macOS High Sierra and Ubuntu Xenial) is reporting an issue at line 196 when it's really at line 208. Pyflakes 2.0.0 did not report the issue at all.

To reproduce:

```console
$ pip install -U pyflakes
Requirement already up-to-date: pyflakes in /usr/local/lib/python3.7/site-packages (2.1.0)
$ wget https://raw.githubusercontent.com/python-pillow/Pillow/a656a0bd603bcc333184ad1baf61d118925b3772/Tests/test_file_libtiff.py
--2019-01-30 11:03:02--  https://raw.githubusercontent.com/python-pillow/Pillow/a656a0bd603bcc333184ad1baf61d118925b3772/Tests/test_file_libtiff.py
Resolving raw.githubusercontent.com (raw.githubusercontent.com)... 151.101.244.133
Connecting to raw.githubusercontent.com (raw.githubusercontent.com)|151.101.244.133|:443... connected.
HTTP request sent, awaiting response... 200 OK
Length: 23915 (23K) [text/plain]
Saving to: ‘test_file_libtiff.py’

test_file_libtiff.py               100%[==============================================================>]  23.35K  --.-KB/s    in 0.001s

2019-01-30 11:03:02 (15.9 MB/s) - ‘test_file_libtiff.py’ saved [23915/23915]

$ pyflakes test_file_libtiff.py
test_file_libtiff.py:196: syntax error in type comment 'dummy value'
$ grep --line-number "dummy value" test_file_libtiff.py
208:        # type: dummy value
```

File on GitHub:

https://github.com/python-pillow/Pillow/blob/a656a0bd603bcc333184ad1baf61d118925b3772/Tests/test_file_libtiff.py#L208
