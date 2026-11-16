Possible memory leak in the CookieJar
### Describe the bug

Memory usage increases indefinitely when making requests with aiohttp>=3.10.0 ClientSession to a server that often sets cookies.

### To Reproduce

```python
import asyncio

async def do_test():
    from aiohttp import ClientSession
    from pprint import pprint

    async with ClientSession() as cs:
        for i in range(10):
            async with cs.get(f'http://httpbin.org/cookies/set/test/val{i}', allow_redirects=False) as r:
                print(f'{len(cs.cookie_jar._cookies)=}', end=' ')
                print(f'{r.headers["set-cookie"]=}')

        print('='*40)
        pprint(dict(cs.cookie_jar._cookies))

if __name__ == '__main__':
    asyncio.run(do_test())
```

### Expected behavior

Eventual decrease in memory usage.

### Logs/tracebacks

```python-traceback
len(cs.cookie_jar._cookies)=1 r.headers["set-cookie"]='test=val0; Path=/'
len(cs.cookie_jar._cookies)=11 r.headers["set-cookie"]='test=val1; Path=/'
len(cs.cookie_jar._cookies)=13 r.headers["set-cookie"]='test=val2; Path=/'
len(cs.cookie_jar._cookies)=15 r.headers["set-cookie"]='test=val3; Path=/'
len(cs.cookie_jar._cookies)=17 r.headers["set-cookie"]='test=val4; Path=/'
len(cs.cookie_jar._cookies)=19 r.headers["set-cookie"]='test=val5; Path=/'
len(cs.cookie_jar._cookies)=21 r.headers["set-cookie"]='test=val6; Path=/'
len(cs.cookie_jar._cookies)=23 r.headers["set-cookie"]='test=val7; Path=/'
len(cs.cookie_jar._cookies)=25 r.headers["set-cookie"]='test=val8; Path=/'
len(cs.cookie_jar._cookies)=27 r.headers["set-cookie"]='test=val9; Path=/'
========================================
{('', ''): <SimpleCookie: >,
 ('httpbin.org', ''): <SimpleCookie: test='val9'>,
 ('httpbin.org', '/cookies'): <SimpleCookie: >,
 ('httpbin.org', '/cookies/set'): <SimpleCookie: >,
 ('httpbin.org', '/cookies/set/test'): <SimpleCookie: >,
 ('httpbin.org', '/cookies/set/test/val1'): <SimpleCookie: >,
 ('httpbin.org', '/cookies/set/test/val2'): <SimpleCookie: >,
 ('httpbin.org', '/cookies/set/test/val3'): <SimpleCookie: >,
 ('httpbin.org', '/cookies/set/test/val4'): <SimpleCookie: >,
 ('httpbin.org', '/cookies/set/test/val5'): <SimpleCookie: >,
 ('httpbin.org', '/cookies/set/test/val6'): <SimpleCookie: >,
 ('httpbin.org', '/cookies/set/test/val7'): <SimpleCookie: >,
 ('httpbin.org', '/cookies/set/test/val8'): <SimpleCookie: >,
 ('httpbin.org', '/cookies/set/test/val9'): <SimpleCookie: >,
 ('org', ''): <SimpleCookie: >,
 ('org', '/cookies'): <SimpleCookie: >,
 ('org', '/cookies/set'): <SimpleCookie: >,
 ('org', '/cookies/set/test'): <SimpleCookie: >,
 ('org', '/cookies/set/test/val1'): <SimpleCookie: >,
 ('org', '/cookies/set/test/val2'): <SimpleCookie: >,
 ('org', '/cookies/set/test/val3'): <SimpleCookie: >,
 ('org', '/cookies/set/test/val4'): <SimpleCookie: >,
 ('org', '/cookies/set/test/val5'): <SimpleCookie: >,
 ('org', '/cookies/set/test/val6'): <SimpleCookie: >,
 ('org', '/cookies/set/test/val7'): <SimpleCookie: >,
 ('org', '/cookies/set/test/val8'): <SimpleCookie: >,
 ('org', '/cookies/set/test/val9'): <SimpleCookie: >}
```

### Python Version

```console
3.8.16
```

### aiohttp Version

```console
3.10.11
```

### multidict Version

```console
6.1.0
```

### propcache Version

```console
0.2.0
```

### yarl Version

```console
1.15.2
```

### OS

Linux

### Related component

Client

### Additional context

I use a single session for the app's lifetime, with requests being sent to the single host.
In the span of weeks memory usage increases from ~100Mb to ~5Gb, never decreasing; aiohttp<=3.9.5 does not show such behavior.
In the test script output notice increasing `len(cs.cookie_jar._cookies)`, for some reason despite the server setting a cookie with `Path=/` CookieJar creates records for every possible path prefix of every request made, and it seems those never get cleaned.

I'm not sure if this is a bug or necesary behaviuor though.

### Code of Conduct

- [x] I agree to follow the aio-libs Code of Conduct

### Additional contract requirements

- `CookieJar.filter_cookies()` must not add new entries to the jar's internal
  `_cookies` mapping for URL paths that have no matching cookies. The number of
  entries in `_cookies` must not grow as `filter_cookies()` is called with
  arbitrarily many distinct paths that have no matching cookies.
- With one cookie valid for every path, after calling `filter_cookies()` for 1,000 distinct paths and then another 1,000 distinct paths, the `_cookies` mapping must gain fewer than 500 entries during the second batch.
