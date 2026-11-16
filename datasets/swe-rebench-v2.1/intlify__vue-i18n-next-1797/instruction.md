Hyphens in placeholders causing error `Unterminated closing brace` in vue-i18n@9
### Reporting a bug?

Using a placeholder with hyphens in vue-i18n@9.11.1 is causing errors

```js
const messages = {
  en: {
    message: {
      "message-with-placeholder-using-hyphens":
        "My message with {placeholder-hyphens}.",
    },
  },
};
// usage:
 $t("message.message-with-placeholder-using-hyphens", {
   "placeholder-hyphens": 'XXXX'
});
```

Error message
```Message compilation error: Unterminated closing brace
1  |  My message with {placeholder-hyphens}.
```

Using `<i18n-t>` is breaking component rendering
```
<i18n-t
      keypath="message.message-with-placeholder-using-hyphens"
      v-if="false"
    >
      <template #placeholder-hyphens>
        {{ $t("message.hello") }}
      </template>
    </i18n-t>
```
Demo: https://codesandbox.io/p/devbox/vuei18n-hyphen-vxst9x?file=%2Fsrc%2FApp.vue
(`<i18n>` can be enabled via `v-if="true"`)

### Expected behavior

Above message-syntax works in vue-i18n@8


### Reproduction

https://codesandbox.io/p/devbox/vuei18n-hyphen-vxst9x?file=%2Fsrc%2FApp.vue


### System Info

```shell
System:
    OS: Windows 11 10.0.22631
    CPU: (20) x64 13th Gen Intel(R) Core(TM) i7-13700H
    Memory: 20.88 GB / 63.68 GB
  Binaries:
    Node: 20.9.0 - C:\Program Files\nodejs\node.EXE
    npm: 6.14.18 - C:\Program Files\nodejs\npm.CMD
  Browsers:
    Edge: Chromium (123.0.2420.81)
    Internet Explorer: 11.0.22621.1
```


### Screenshot

$t error and output
![image](https://github.com/kazupon/vue-i18n/assets/1399149/3865551d-c249-4f65-9339-948e1936aafe)
![image](https://github.com/kazupon/vue-i18n/assets/1399149/c07076dc-f111-47e3-8df2-948365eab4ad)


`<i18n-t>` error
![image](https://github.com/kazupon/vue-i18n/assets/1399149/495b74ca-e5e2-4aa2-a3ed-3db831a48d0e)



### Additional context

_No response_

### Validations

- [X] Read the [Contributing Guidelines](https://github.com/intlify/vue-i18n-next/blob/master/.github/CONTRIBUTING.md)
- [X] Read the [Documentation](https://vue-i18n.intlify.dev/)
- [X] Check that there isn't [already an issue](https://github.com/intlify/vue-i18n-next/issues) that reports the same bug to avoid creating a duplicate.
- [X] Check that this is a concrete bug. For Q&A open a [GitHub Discussions](https://github.com/intlify/vue-i18n-next/discussions)
