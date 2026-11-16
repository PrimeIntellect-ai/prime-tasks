Feature request: easily mock cookies
It would be super nice if we could do something like this:

```python
respx.get("example.com").respond(cookies={"foo": "bar"})

cookies = httpx.Cookies()
respx.get("example.com").respond(cookies=cookies)
```
