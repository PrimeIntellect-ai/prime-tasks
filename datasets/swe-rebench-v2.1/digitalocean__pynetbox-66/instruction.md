v2.3.4 of NetBox adds an extra backslash ("/") between hostname and URL
### Issue type
[X] Bug report      <!-- Unexpected or erroneous behavior -->

### Environment
* Python version:  3.5
* NetBox version:  2.3.4
* PyNetBox version: 3.3.1

### Description
Using `pynetbox` querying against an instance of `NetBox` running `v2.3.3` works fine.
However, when I switch the URL to an instance of `NetBox` running `v2.3.4`, it stops working.

The details and code for each version are below (the same exact data is in both versions of `NetBox`).

---

(`v2.3.3`)
```
>>> try:
...     nb.dcim.sites.get(slug='0am')
... except pynetbox.lib.query.RequestError as e:
...     print(e.req.url)
...
0am
```

---

(`v2.3.4`)
```
>>> try:
...     nb.dcim.sites.get(slug='0am')
... except pynetbox.lib.query.RequestError as e:
...     print(e)
...
The request failed with code 404 Not Found
>>> try:
...     nb.dcim.sites.get(slug='0am')
... except pynetbox.lib.query.RequestError as e:
...     print(e.req.url)
...
http://myhost:8080//api/dcim/sites/?slug=0am
```

---

Notice the extra `/` between the hostname and the rest of the URL?
I'm close to positive that is what is causing the issue.
However, when using the `SwaggerUI` and performing the same action via a `PUT` request, no issues.
So I'm not sure if the error exists in `NetBox` since that is what changed or `pynetbox` since everything **else** in `v2.3.4` works fine.

### Additional contract requirements

When a request is made using a NetBox root URL that ends in `/`, the resulting request URL must have a single separator before `/api` (for example, `/api/...`, not `//api/...`).
