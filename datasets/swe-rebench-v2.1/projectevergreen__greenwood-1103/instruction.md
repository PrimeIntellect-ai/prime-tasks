not found static assets are returning 500 status code when running the `serve` command
## Type of Change
Bug

## Summary
Noticing that when running `greenwood serve` and accessing a static asset that doesn't exist, the browser is getting a `500` error instead of a `404`.

![Screen Shot 2023-04-29 at 10 41 26 AM](https://user-images.githubusercontent.com/895923/235308620-eb8c077e-f28c-4a14-bfa7-798ac2fbe60d.png)

## Details
In the terminal there is also an ugly error as well
```sh
[Error: ENOENT: no such file or directory, open '/Users/analogstudios/Workspace/analogstudios/repos/www.blissfestri.com/public/foo.png'] {
  errno: -2,
  code: 'ENOENT',
  syscall: 'open',
  path: '/Users/analogstudios/Workspace/analogstudios/repos/www.blissfestri.com/public/foo.png'
}
```

### Additional contract requirements

- When `greenwood serve` receives a request for a static asset that does not exist, it must return HTTP 404 and must not report the resulting missing-file `ENOENT` as a terminal error.
