disabled, checkedを普通のinputやselectやtextarea要素につけた場合に、aria-disabled, aria-checkedと同等の表示をする
#106 で追加したもののうち、HTMLのネイティブセマンティクスで同じことができるものを同じ表示にしたい

### Additional contract requirements

- The mirrored native state is reported with the same `ariaStatus.<state>.<value>` content format already used for ARIA state display, for example `ariaStatus.aria-checked.true`, `ariaStatus.aria-checked.false` and `ariaStatus.aria-disabled.true`.
