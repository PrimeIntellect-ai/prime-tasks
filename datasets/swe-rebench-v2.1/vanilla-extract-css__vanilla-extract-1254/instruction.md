Custom identifier doesn't allow hyphens inside a css class
### Describe the bug

Custom identifier function throws an error, when trying to use css class with hyphens inside.

```javascript
const withVanillaExtract = createVanillaExtractPlugin({
    identifiers: ({ hash }) => `prefix-${hash}` //will throw an Error
});
```

It seems the regex detects the false negative result.
[HIDDEN]



### Reproduction

https://github.com/EvgenNoskov/vanilla-css-issue

### System Info

```shell
System:
    OS: Windows 10 10.0.19045
    CPU: (8) x64 Intel(R) Core(TM) i7-6700 CPU @ 3.40GHz
    Memory: 7.59 GB / 31.94 GB
  Binaries:
    Node: 20.10.0 - C:\Program Files\nodejs\node.EXE
    Yarn: 1.22.10 - ~\AppData\Roaming\npm\yarn.CMD
    npm: 10.2.3 - C:\Program Files\nodejs\npm.CMD
  Browsers:
    Chrome: 120.0.6099.71
    Edge: Spartan (44.19041.3636.0), Chromium (120.0.2210.61)
    Internet Explorer: 11.0.19041.3636
  npmPackages:
    @vanilla-extract/css: ^1.14.0 => 1.14.0
    @vanilla-extract/next-plugin: ^2.3.2 => 2.3.2
```


### Used Package Manager

npm

### Logs

```shell
Error: Identifier function returned invalid indentifier: "prefix-1gezp2d0"
Import trace for requested module:
./src/components/MyComponent.css.ts
./src/components/MyComponent.tsx
./src/app/page.tsx
```


### Validations

- [X] Check that there isn't [already an issue](https://github.com/vanilla-extract-css/vanilla-extract/issues) that reports the same bug to avoid creating a duplicate.
- [X] The provided reproduction is a [minimal reproducible example](https://stackoverflow.com/help/minimal-reproducible-example) of the bug.

### Additional contract requirements

- A custom identifier function must allow an identifier containing an internal hyphen when generating a CSS class, such as `prefix-${hash}`; it must not reject the identifier solely because it contains a hyphen.
