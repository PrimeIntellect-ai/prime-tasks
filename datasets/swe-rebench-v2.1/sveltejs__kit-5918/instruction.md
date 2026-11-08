`errors` exported by `+page.svelte` is only available on the server and not on the client
### Describe the bug

Cannot access the `errors` object in the client returned by actions (`+page.server.js`).

### Reproduction

https://github.com/pilcrowOnPaper/sveltekit-action-issue

Description and steps are described in the repo README

### Logs

 (Browser console)
```shell
<Root> was created without expected prop 'errors'
```


### System Info

```shell
System:
    OS: macOS 12.5
    CPU: (8) x64 Intel(R) Core(TM) i7-1060NG7 CPU @ 1.20GHz
    Memory: 870.41 MB / 16.00 GB
    Shell: 5.8.1 - /bin/zsh
Binaries:
    Node: 18.7.0 - ~/.nvm/versions/node/v18.7.0/bin/node
    Yarn: 1.22.19 - /usr/local/bin/yarn
    npm: 8.15.0 - ~/.nvm/versions/node/v18.7.0/bin/npm
Browsers:
    Chrome: 98.0.4758.102
    Firefox: 103.0.2
    Safari: 15.6
npmPackages:
    @sveltejs/adapter-auto: next => 1.0.0-next.64
    @sveltejs/kit: next => 1.0.0-next.408
    svelte: ^3.44.0 => 3.49.0
    vite: ^3.0.0 => 3.0.7
```

Tested with: Safari, Firefox, Chrome


### Severity

blocking an upgrade

### Additional Information

_No response_
