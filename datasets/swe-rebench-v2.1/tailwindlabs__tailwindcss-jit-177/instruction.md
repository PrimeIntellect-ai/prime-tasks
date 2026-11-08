JIT does not work when prefix callback is specified
### What version of @tailwindcss/jit are you using?

0.1.10

### What version of Node.js are you using?

15.9.0

### What browser are you using?

all of them

### What operating system are you using?

macOS

### Reproduction repository

https://github.com/signor-pedro/tailwind-repro

Commenting this out makes JIT work
```
prefix(selector) {
    if (['.align-bottom', '.ml-1'].includes(selector)) {
      return 'tw-';
    }

    return '';
  },
```
