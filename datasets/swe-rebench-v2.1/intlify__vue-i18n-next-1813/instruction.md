Linked messages doesn't support chinese character as key
### Reporting a bug?

when use this feature like `audit @:状态`, it won't work as expected.

### Expected behavior

Linked message with chinese as key can work.

### Reproduction

https://stackblitz.com/edit/vitejs-vite-ju6nqb?file=src%2Fmain.ts

### System Info

```shell
System:
    OS: Windows 11 10.0.22621
    CPU: (8) x64 Intel(R) Core(TM) i7-9700 CPU @ 3.00GHz
    Memory: 10.39 GB / 31.89 GB
  Binaries:
    Node: 21.7.3 - C:\Program Files\nodejs\node.EXE
    Yarn: 1.22.18 - ~\env\npmDownload\packages\yarn.CMD
    npm: 9.6.2 - ~\env\npmDownload\packages\npm.CMD
    pnpm: 8.13.1 - ~\env\npmDownload\pnpm\pnpm.EXE
  Browsers:
    Edge: Chromium (123.0.2420.97)
    Internet Explorer: 11.0.22621.1
```


### Screenshot

![image](https://github.com/intlify/vue-i18n-next/assets/30925732/41f0171d-996e-40b5-b344-9a5e70e98baf)


### Additional context

Use our native language as the translation key can help read page code more easily without some IDE a11y plugin. When use chinese , in most case it worked, now I found only this feature get some problem.

_No response_

### Validations

- [X] Read the [Contributing Guidelines](https://github.com/intlify/vue-i18n-next/blob/master/.github/CONTRIBUTING.md)
- [X] Read the [Documentation](https://vue-i18n.intlify.dev/)
- [X] Check that there isn't [already an issue](https://github.com/intlify/vue-i18n-next/issues) that reports the same bug to avoid creating a duplicate.
- [X] Check that this is a concrete bug. For Q&A open a [GitHub Discussions](https://github.com/intlify/vue-i18n-next/discussions)
