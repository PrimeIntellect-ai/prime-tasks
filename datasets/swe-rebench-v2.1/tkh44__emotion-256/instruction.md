Nested selectors don't work if the parent doesn't contains at least one CSS declaration
- `emotion` version: 7.0.13

I wanted to apply a style to all elements of class `foo` that are inside `bar`:

```javascript
import { css } from 'emotion';

const foo = css`
  color: blue;
`;
const bar = css`
  & .${foo} {
    color: red;
  }
`;
```

but instead this was all of the output styles:

```css
.css-bithoy{color:blue;}
```

as if I wrote this:

```js
const foo = css`
  color: blue;
`;
const bar = css`
  ${foo};
`;
```

However, if I add a declaration for `bar`:

```js
const bar = css`
  color: black;
  & .${foo} {
    color: red;
  }
`;
```

it works as expected:

```css
.css-bithoy{color:blue;}
.css-6fp6m3{color:black;}
.css-6fp6m3 .css-bithoy{color:red;}
```
