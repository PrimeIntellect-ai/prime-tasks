gradientColorStops behaves differently
### What version of @tailwindcss/jit are you using?

v0.1.4

### What version of Node.js are you using?

14.10.1

### What browser are you using?

Chrome

### What operating system are you using?

Windows 10

### Reproduction repository

https://github.com/jayars/tailwindcss-jit-gradientcolorstop

Hi,

`gradientColorStops` seems to behave differently when using `@tailwindcss/jit`.

* `tailwindcss`: Custom gradient stops work
* `@tailwindcss/jit`: Custom gradient stops don't work

![image](https://user-images.githubusercontent.com/28939507/111862453-605dfb80-8990-11eb-86e6-d516cc68f4fe.png)

Not sure if this is as-designed or a bug.

`postcss.config.js`
```js
module.exports = {
  plugins: {
    '@tailwindcss/jit': {},
    autoprefixer: {},
  },
}
```

`tailwind.config.js`
```js
module.exports = {
  ...
  theme: {
    extend: {
      gradientColorStops: {
        x: '#b1eafc',
        y: '#fbd7f8'
      }
    }
  }
  ...
}
```


Thanks
