Vue's object-class syntax with a hyphenated key class breaks formatting (v5+)
The error happens in v5+.

When using [this syntax in Vue](https://vuejs.org/guide/essentials/class-and-style#binding-to-objects), where we can use objects to dynamically assign CSS classes, if the key of the object is a hyphenated string, it breaks Prettier's ability to format.

## Steps to reproduce
Create a component in Vue, as simple as:
```
<template>
  <div
    :class="{
        'bg-black': true
    }">Some text</div>
</template>
```

## Expected behavior
Prettier formats correctly

## Actual behavior
Formatting stops and this error is shown in the OUTPUT tab for Prettier:

![Screenshot 2024-02-15 at 8 51 51 p m](https://github.com/francoismassart/eslint-plugin-tailwindcss/assets/31573181/f3d08500-b824-48be-a55c-f26a001bad1d)

## Extra info
Been using these 3 plugins together so far `"prettier-plugin-tailwindcss", "prettier-plugin-classnames", "prettier-plugin-merge"` without issue, until I found this one.

Even if I only use `prettier-plugin-classnames`, the error happens.

If I don't use a hyphenated string as key, the error goes away. For example, this works fine:

```
<template>
  <div
    :class="{
        absolute: true
    }">Some text</div>
</template>
```

 - OS: macOS Sonoma 14.1.1
 -  VSCode 1.86.1
 -  Prettier ^3.2.5
