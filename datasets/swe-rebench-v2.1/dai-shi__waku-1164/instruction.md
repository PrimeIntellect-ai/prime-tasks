Remove prettier format step from generation and add formatter ignore comments
remove prettier formatting from: [HIDDEN]

Ignore recommendations for:

- [deno fmt](https://docs.deno.com/runtime/reference/cli/fmt)
- [Prettier](https://prettier.io/)
- ~[Biome](https://biomejs.dev/formatter)~
- ~[dprint](https://dprint.dev/)~

plan for fixing: https://github.com/dai-shi/waku/issues/1148#issuecomment-2599867558

### Additional contract requirements

- Generated type files must not be passed through Prettier formatting. Include formatter-ignore comments so Prettier and `deno fmt` leave the generated output unchanged.
