[Proposal] Use system font stack for Base UI
Design is revisiting the type for the internal version of Base UI, and as part of that we'd like to take a stronger opinion on a typeface for the open-source version, i.e. using the system font stack instead of Helvetica.

Looking at what the new type looks like compared to various other typefaces (San Francisco, Helvetica) you can see, the new font for body text is proportionally similar to San Francisco, which would help make the open-source and non-open-source versions look more consistent, at least on Macs. And, as a plus, it would help make re-creating layouts much easier :)

Would love to hear some thoughts—we're still in the early stages of all of this.

### Additional contract requirements

- The font-family value rendered for Input's StyledInputContainer must be `system-ui, "Helvetica Neue", arial, sans-serif`.
