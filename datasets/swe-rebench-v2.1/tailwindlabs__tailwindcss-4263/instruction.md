[JIT] font/text size does not support css variables
### What version of Tailwind CSS are you using?

2.1.0

### What build tool (or framework if it abstracts the build tool) are you using?

postcss8

### What version of Node.js are you using?

15.14.0

### What browser are you using?

Firefox

### What operating system are you using?

Arch Linux

### Reproduction repository

See comment

### Describe your issue

Hey guys!
I try to implement fluid font sizes according to https://www.smashingmagazine.com/2021/04/designing-developing-fluid-type-space-scales/

I have [generated the following pattern](https://utopia.fyi/type/calculator):
```css
/* @link https://utopia.fyi/type/calculator?c=320,21,1.2,1140,24,1.25,5,2,&s=0.75|0.5|0.25,1.5|2|3|4|6,s-l */

:root {
  --step--2: clamp(0.91rem, 0.89rem + 0.10vw, 0.96rem);
  --step--1: clamp(1.09rem, 1.05rem + 0.21vw, 1.20rem);
  --step-0: clamp(1.31rem, 1.24rem + 0.37vw, 1.50rem);
  --step-1: clamp(1.58rem, 1.46rem + 0.59vw, 1.88rem);
  --step-2: clamp(1.89rem, 1.71rem + 0.89vw, 2.34rem);
  --step-3: clamp(2.27rem, 2.01rem + 1.29vw, 2.93rem);
  --step-4: clamp(2.72rem, 2.36rem + 1.83vw, 3.66rem);
  --step-5: clamp(3.27rem, 2.75rem + 2.56vw, 4.58rem);
}
```

But the syntax `text-[var(--step-5)]` does not work. Using a fixed pixel size works, and using the style inline also works.

```html
<div class="text-[var(--step-5)]">test1</div>

<div class="text-[50px]">test2</div>

<div style="font-size: var(--step-5);">test3</div>
```

### Additional contract requirements

- Inside the square brackets of an arbitrary value, a type name followed by a colon (for example `length:`) may precede the value to state what kind of value it is. The type prefix is removed from the generated CSS value.
- `text-[length:var(--step-5)]` must generate a rule for the class with the selector `.text-\[length\:var\(--step-5\)\]` whose only declaration is `font-size: var(--step-5);`, so the font size of an element can be driven by a CSS custom property.
