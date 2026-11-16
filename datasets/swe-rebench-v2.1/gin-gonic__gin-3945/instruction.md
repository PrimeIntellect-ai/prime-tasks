Warning link doesn't point to anything anymore
The following warning points to a nonexistent link:
```
[GIN-debug] [WARNING] You trusted all proxies, this is NOT safe. We recommend you to set a value.
Please check https://pkg.go.dev/github.com/gin-gonic/gin#readme-don-t-trust-all-proxies for details.
```
## Environment

- go version: 1.22.2
- gin version (or commit ref): v1.9.1
- operating system: Linux

### Additional contract requirements

- When the server starts while every proxy is trusted, the printed "You trusted all proxies" warning must point to the project's own documentation section on not trusting all proxies (the "Don't trust all proxies" section of the repository's docs), and must not point to a link that does not exist.
