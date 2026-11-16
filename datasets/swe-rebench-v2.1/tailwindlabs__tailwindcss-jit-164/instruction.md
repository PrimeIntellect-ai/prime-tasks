dashes in theme key naming in Tailwind config
### What version of @tailwindcss/jit are you using?

v0.1.10

### What version of Node.js are you using?

v14.15.5

### What browser are you using?

Chrome, Brave

### What operating system are you using?

macOS

### Reproduction repository

this was a fun listen: https://www.youtube.com/watch?v=ez773teNFYA

We just recently switched to using the JIT compiler as our Tailwind engine, and started to run into the described issue.

Prior to switch to the JIT, the below (simplified) theme object in our Tailwind config file worked just fine.
```
theme: {
    extend: {
      backgroundImage: {
        'hero--home-1': "url('/images/homepage-1.jpg')"
      },
      colors: {
        'custom--color-0': '#614c3a'
      }
  }
```
After the switch, not so much.
In the isolated case of `hero--home-1`, there wasn't any generated `bg-hero--home-1` class in our output CSS file -- though the project overall would build and run fine without any generated error or warning message.
In the isolated case of `custom--color-0`, the build process generates the following error message:
```
CssSyntaxError: /Users/dane/Documents/work/skipper/programs/marram_montauk/styles/global.css:68:9: The `text-custom--color-0` class does not exist. If `text-custom--color-0` is a custom class, make sure it is defined within a `@layer` directive.
    at Input.error (/Users/dane/Documents/work/skipper/programs/marram_montauk/node_modules/postcss/lib/input.js:121:16)
    at AtRule.error (/Users/dane/Documents/work/skipper/programs/marram_montauk/node_modules/postcss/lib/node.js:59:32)
    at processApply (/Users/dane/Documents/work/skipper/programs/marram_montauk/node_modules/@tailwindcss/jit/src/lib/expandApplyAtRules.js:158:23)
    at /Users/dane/Documents/work/skipper/programs/marram_montauk/node_modules/@tailwindcss/jit/src/lib/expandApplyAtRules.js:218:5
    at LazyResult.runOnRoot (/Users/dane/Documents/work/skipper/programs/marram_montauk/node_modules/postcss/lib/lazy-result.js:303:16)
    at LazyResult.runAsync (/Users/dane/Documents/work/skipper/programs/marram_montauk/node_modules/postcss/lib/lazy-result.js:355:26)
    at LazyResult.async (/Users/dane/Documents/work/skipper/programs/marram_montauk/node_modules/postcss/lib/lazy-result.js:205:30)
    at LazyResult.then (/Users/dane/Documents/work/skipper/programs/marram_montauk/node_modules/postcss/lib/lazy-result.js:190:17) {
  reason: 'The `text-custom--color-0` class does not exist. If `text-custom--color-0` is a custom class, make sure it is defined within a `@layer` directive.'
```

_However_, when I change our theme object keys such that the `--` are replaced by `-`, ala
```
theme: {
    extend: {
      backgroundImage: {
        'hero-home-1': "url('/images/homepage-1.jpg')"
      },
      colors: {
        'custom-color-0': '#614c3a'
      }
  }
```
Everything works well
Thank you!
