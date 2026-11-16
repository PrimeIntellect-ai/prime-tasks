[comp:button]button components
- [x] I have searched the [issues](https://github.com/IduxFE/components/issues) of this repository and believe that this is not a duplicate.

### What problem does this feature solve?

### What does the proposed API look like?

### `ix-button`

> 当 `mode` 不为 `link` 时，除以下表格之外还支持原生 `button` 的[所有属性](https://developer.mozilla.org/zh-CN/docs/Web/HTML/Element/button)。
> 当 `mode` 为 `link` 时，除以下表格之外还支持原生 `a` 的[所有属性](https://developer.mozilla.org/zh-CN/docs/Web/HTML/Element/a)。

| 属性 | 说明 | 类型  | 全局配置 |
| --- | --- | --- | --- |
| `mode` | 设置按钮种类 | `'primary'|'default'|'dashed'|'text'|'link'` | `'default'` |
| `danger` | 设置危险状态 | `boolean` | - |
| `ghost` | 设置幽灵状态 | `boolean` | - |
| `disabled` | 设置禁用状态 | `boolean` | - |
| `loading` | 设置加载中状态 | `boolean` |  - |
| `size` | 设置按钮大小 | `'large'|'medium'|'small'` | `'medium'` |
| `shape` | 设置按钮形状 | `'circle'|'round'` | - |
| `block` | 将按钮宽度调整为其父宽度的选项 | `boolean` | - |
| `icon` | 设置图标类型(loading 状态时无效) | `string` | - |

### `ix-button-group`

| 属性 | 说明 | 类型  | 全局配置 |
| --- | --- | --- | --- |
| `mode` | 设置组内按钮种类， | `'primary'|'default'|'dashed'|'text'|'link'` | - |
| `size` | 设置组内按钮大小 | `'large'|'medium'|'small'` | - |
| `shape` | 设置组内按钮形状 | `'circle'|'round'` | - |

### Additional contract requirements

- The button component is exported as `Button` from `packages/components/button/src/Button.vue` and accepts the props `ButtonProps` declared in `packages/components/button/src/types.ts`.
- The button group component is exported as `ButtonGroup` from `packages/components/button/src/ButtonGroup.vue` and accepts the props `ButtonGroupProps` declared in `packages/components/button/src/types.ts`.
- `ButtonProps` contains `mode`, `danger`, `ghost`, `disabled`, `loading`, `size`, `shape`, `block` and `icon`; `ButtonGroupProps` contains `mode`, `size` and `shape`; `ButtonShape` is `'circle' | 'round'`.
- A button renders a `<button>` element for every `mode` except `'link'`, for which it renders an `<a>` element.
- The root element of a button always carries the class `ix-button`.
- A button whose `mode` is not `'default'` carries the class `ix-button-{mode}`.
- A button whose `size` is not `'medium'` carries the class `ix-button-{size}`.
- A button with a `shape` carries the class `ix-button-{shape}`.
- `danger`, `ghost`, `disabled`, `loading` and `block` add the classes `ix-button-danger`, `ix-button-ghost`, `ix-button-disabled`, `ix-button-loading` and `ix-button-block` respectively.
- When `loading` is set the button shows an element with the class `ix-icon-loading`; otherwise, when `icon` is set, it shows an element with the class `ix-icon-{icon}`.
- Slot content is rendered after any icon.
- The root element's `disabled` attribute is present when `disabled` or `loading` is set.
- A button group renders a `<div>` element carrying the class `ix-button-group`.
