safety: `safeify_url()` function can't handle (invalid) URLs with `[hostname]` placeholder
If someone sends a link while `safety` is active in the channel, and the URL contains a placeholder hostname in square brackets, Sopel will spit out an "Unexpected ValueError" message. **Note: Seems to happen only on Python 3.11 or higher.**

This is from the `safeify_url()` function added in #2279, which uses `urllib.parse.urlparse()` to make sanitizing URL parts easier, which in turn uses `ipaddress.ip_address()` to raise an error for bracketed IPv4 addresses—and trips on this weird edge case:

https://github.com/sopel-irc/sopel/blob/e7d86481d186f2faafa01cc46131485d2b4966d4/sopel/builtins/safety.py#L127-L133

Simple examples using the Python console:

```pycon
>>> # Python 3.10
>>> safety.safeify_url('http://[Target-IP]/cgi-bin/account_mgr.cgi')
'hxxp://[Target-IP]/cgi-bin/account_mgr.cgi'
```

```pycon
>>> # Python 3.11
>>> safety.safeify_url('http://[Target-IP]/cgi-bin/account_mgr.cgi')
Traceback (most recent call last):
  File "<stdin>", line 1, in <module>
  File "/home/dgw/github/sopel-irc/sopel/sopel/builtins/safety.py", line 129, in safeify_url
    parts = urlparse(url)
            ^^^^^^^^^^^^^
  File "/home/dgw/.pyenv/versions/3.11.10/lib/python3.11/urllib/parse.py", line 395, in urlparse
    splitresult = urlsplit(url, scheme, allow_fragments)
                  ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/home/dgw/.pyenv/versions/3.11.10/lib/python3.11/urllib/parse.py", line 500, in urlsplit
    _check_bracketed_host(bracketed_host)
  File "/home/dgw/.pyenv/versions/3.11.10/lib/python3.11/urllib/parse.py", line 446, in _check_bracketed_host
    ip = ipaddress.ip_address(hostname) # Throws Value Error if not IPv6 or IPv4
         ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/home/dgw/.pyenv/versions/3.11.10/lib/python3.11/ipaddress.py", line 54, in ip_address
    raise ValueError(f'{address!r} does not appear to be an IPv4 or IPv6 address')
ValueError: 'Target-IP' does not appear to be an IPv4 or IPv6 address
```

The version inconsistency is going to be the worst part of designing a "correct" fix for this. A simple fallback approach (such as `return url.replace('http', 'hxxp', 1) if url.startswith('http') else url`) will miss more complicated cases that are still handled fine in older Python versions (output using 3.10 shown here):

```pycon
>>> safety.safeify_url('http://[Target.IP]/cgi-bin/account_mgr.cgi')  # dot gets bracketed
'hxxp://[Target[.]IP]/cgi-bin/account_mgr.cgi'
>>> safety.safeify_url('http://[Target:IP]/cgi-bin/account_mgr.cgi')  # colon gets bracketed
'hxxp://[Target[:]IP]/cgi-bin/account_mgr.cgi'
```

_Do note though that all this is an edge case of an edge case. People must intentionally construct these invalid URLs, and can be trained to simply use another type of bracket for placeholders instead, such as `http://<Target-IP>/cgi-bin/account_mgr.cgi`._

### Additional contract requirements

- The public function is `safeify_url(url: str) -> str`, located in module `sopel.builtins.safety`.
- For `http://[fd00:::]/`, the returned value is either `hxxp://[fd00[:][:][:]]/` or `http[:]//[fd00[:][:][:]]/`.
- For `http://[placeholder]/`, the returned value is either `hxxp://[placeholder]/` or `http[:]//[placeholder]/`.
