Cannot use derived state -  Internal server error: ancestors.at is not a function
**Describe the bug**
whenever im creating a derived state, it gave me an error.

**To Reproduce**
Here's my code:
```
let $name = 'jesen'

let $width = 10;
let $height = 20;
let $area = $width * $height

export const TestComponent = () => {
    return (
        <div>
            <div>Hallo, {$name}</div>
            <div>width: {$width}</div>
            <div>height: {$height}</div>
            <div>area: {$area}</div>
        </div>
    )
}
```

**Expected behavior**
the $area variable should give me a calculated value based on the width and height.

**Screenshots**
If applicable, add screenshots to help explain your problem.

**Desktop (please complete the following information):**
 - OS: Windows 11
 - Browser: Brave
 - Version 1.58.131

**Additional context**
here's the full error:
```12:13:11 PM [vite] page reload src/components/TestComponent.tsx
ancestors.at is not a function
12:13:12 PM [vite] Internal server error: ancestors.at is not a function
  Plugin: transform-rezact
  File: C:/Users/jesse/rezact-project/rezact-project/src/components/TestComponent.tsx
      at BinaryExpression (file:///C:/Users/jesse/rezact-project/rezact-project/node_modules/@rezact/rezact/vite-plugin.js:510:109)
      at c (file:///C:/Users/jesse/rezact-project/rezact-project/node_modules/@rezact/rezact/magic-string.es-d610b484.js:6789:18)
      at Object.skipThrough (file:///C:/Users/jesse/rezact-project/rezact-project/node_modules/@rezact/rezact/magic-string.es-d610b484.js:6794:37)
      at c (file:///C:/Users/jesse/rezact-project/rezact-project/node_modules/@rezact/rezact/magic-string.es-d610b484.js:6788:22)
      at Object.base.VariableDeclarator (file:///C:/Users/jesse/rezact-project/rezact-project/node_modules/@rezact/rezact/magic-string.es-d610b484.js:6893:20)
      at c (file:///C:/Users/jesse/rezact-project/rezact-project/node_modules/@rezact/rezact/magic-string.es-d610b484.js:6788:22)
      at Object.base.VariableDeclaration (file:///C:/Users/jesse/rezact-project/rezact-project/node_modules/@rezact/rezact/magic-string.es-d610b484.js:6888:5)
      at c (file:///C:/Users/jesse/rezact-project/rezact-project/node_modules/@rezact/rezact/magic-string.es-d610b484.js:6788:22)
      at Object.skipThrough (file:///C:/Users/jesse/rezact-project/rezact-project/node_modules/@rezact/rezact/magic-string.es-d610b484.js:6794:37)
      at c (file:///C:/Users/jesse/rezact-project/rezact-project/node_modules/@rezact/rezact/magic-string.es-d610b484.js:6788:22)
```
