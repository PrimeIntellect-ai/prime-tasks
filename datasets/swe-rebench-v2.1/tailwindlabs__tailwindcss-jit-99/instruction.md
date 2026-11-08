Arbitrary styles issue with transition-duration
I tried to change the duration of transition, but jit compiler doesn't apply this. It always applies the default 150ms value.

`transition duration-[250ms]`

Generated css;
```css
.transition {
    transition-property: background-color, border-color, color, fill, stroke, opacity, box-shadow, transform;
    transition-timing-function: cubic-bezier(0.4, 0, 0.2, 1);
    transition-duration: 150ms;
}
```
