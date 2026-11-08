SpaceBeforeBrace New Line
I think there is a bug in the reg ex here: https://github.com/lesshint/lesshint/blob/77a502cb25dd8e8368b9a35aaabd183352d6c03e/lib/linters/space_before_brace.js#L15

It does not allow for whitespace between the selector and the brace so this is allowed

```css
ul
{
//Some Styles
li
{
//Some Styles
}
}
```

But this is not because between li and { there are 4 spaces.
```css
ul
{
    //Some Styles

    li
    {
        //Some Styles
    }
}
```

I think the fix would be to change the regex to /[HIDDEN]/ which would require a return directly after the selector but also allow for tabs or a spaces used to indent the code.

I do not think this is intended behaviour and I am happy to send a pull request but but fixing it would be a breaking change.

### Additional contract requirements

- In `new_line` style, allow the opening brace after exactly one line break following the selector, with spaces and/or tabs before the brace. Do not allow multiple consecutive line breaks between the selector and the brace.
