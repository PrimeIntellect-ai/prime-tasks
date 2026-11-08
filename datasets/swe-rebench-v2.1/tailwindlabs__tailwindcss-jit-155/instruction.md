`@apply` doesn't respect order of sibling declarations within same rule
There are times where you still want to use good old CSS and previously I would add these under my `@apply` statements, and they'd be added to the bottom of the built css file and therefor override tailwind, but with jit they are being added to the top. eg:

**Disclaimer: I know I can do this manual css using tailwinds `bg-opacity-50`  it's just an example...**

## Before JIT
### app.sass
```
.some-div
  @apply bg-blue flex
  background: rgba(0,0,0,0.5)
```
### app.css (Built)
```
.some-div
  background-color: blue
  display: flex
  background-color: rgba(0,0,0,0.5)
```

## After JIT
### app.sass
```
.some-div
  @apply bg-blue flex
  background: rgba(0,0,0,0.5)
```
### app.css (Built)
```
.some-div
  background-color: rgba(0,0,0,0.5)
  background-color: blue
  display: flex
```
