Incorrect "outdated gradient" warning on `background` shorthand
Hi,

This input returns an incorrect warning:

```css
a { background: radial-gradient(#FFF, transparent) 0 0 / cover no-repeat #F0F; }
```

The error:

> 2:2	⚠  Gradient has outdated direction syntax. Replace `cover` to `farthest-corner`. [autoprefixer]

In this context, `cover` is used as the `background-size`, not the `radial-gradient` direction.
