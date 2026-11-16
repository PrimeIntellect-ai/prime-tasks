Group Hover with Custom Separator
### What version of Tailwind CSS are you using?

2.1.2

### What build tool (or framework if it abstracts the build tool) are you using?

postcss-cli 8.2.15

### What version of Node.js are you using?

12

### What browser are you using?

Safari

### What operating system are you using?

macOS

### Reproduction repository

https://play.tailwindcss.com/IccDaYWge7

### Describe your issue

I am using a different separator.

```js
//tailwind.config.js
const colors = require('tailwindcss/colors')
module.exports = {
  separator: '_',
  mode: 'jit',
  purge: ['./src/**/*.{html,ts}'],
  darkMode: 'class', // or 'media' or 'class'
  theme: {
    extend: {
      colors
    },
  },
  variants: {
    extend: {},
  },
  plugins: [
  ],
}
```

When using group hover, in this fashion it does not work.
```html
<div *ngIf="i < 2" class="text-blue-100 text-sm font-semibold bg-blue-600 cursor-pointer rounded-md py-1 px-2 group">
<span class="group-hover_text-blue-500">{{phone.type}}</span>
```

However, the css that is outputted is the following:
```css
.group_hover .group-hover_text-blue-500 {
	--tw-text-opacity: 1;
	color: rgba(59, 130, 246, var(--tw-text-opacity));
}
```

It should look like this:
```css
.group:hover .group-hover_text-blue-500 {
	--tw-text-opacity: 1;
	color: rgba(59, 130, 246, var(--tw-text-opacity));
}
```

When I manually change this, the correct behavior occurs.

I created a tailwind play, to test it out, and notice the same behavior: [https://play.tailwindcss.com/IccDaYWge7](https://play.tailwindcss.com/IccDaYWge7)
