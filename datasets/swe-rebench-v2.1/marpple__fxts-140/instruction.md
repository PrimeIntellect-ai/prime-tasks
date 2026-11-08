The curried function returned from the fxts/curry is incorrectly inferred.
# Bug Report

<!--
  Please fill in each section completely. Thank you!
-->

### 💻 Code

<!-- Please post the relevant code sample here as well-->
<!-- How to reproduce it -->

```ts
import { each, map, pipe, curry } from '@fxts/core';

const add = curry((a: number, b: number) => a + b);

pipe([1, 2, 3], map(add(10)), map(add(100)), each(console.log));
```

### 🙁 Actual behavior

Typescript can't correctly infer the type of add when it executed in map or pipe.

* add(10) in first map
![image](https://user-images.githubusercontent.com/29361570/152823929-2a04fe29-a79c-47f2-bdd8-c3f729cc9864.png)

* add(100) in second map
![image](https://user-images.githubusercontent.com/29361570/152824342-c2dfe4cb-3f80-4b30-8836-dda1df0f142b.png)

More precisely, every functions whose type is compatible with `<X>(f: (...args) => X): X` can't infer if callback is executed curried function.

[HIDDEN]

I think typescript infers type `f: (...args) => X`, not type `X` as the return type of curried function, because `ReturnType` uses the `infer` keyword and Curry passes `R = ReturnType` recursively.

[HIDDEN]


### 🙂 Expected behavior

<!-- What you expected to happen instead, and why -->
* add(10) in first map
![image](https://user-images.githubusercontent.com/29361570/152830379-f7ec06f9-a4f8-47bc-9edb-e4a7acf5a40f.png)


* add(100) in second map
![image](https://user-images.githubusercontent.com/29361570/152830422-08e4fa04-2783-43d6-99fd-b9194d913b2b.png)

---

### Version Information

<!-- Please let me know your environment -->

- Operating system: macOS Big Sur 11.1
- Typescript: ^4.5.4
- Nodejs: v17.3.1

### Additional contract requirements

- `curry(fn)` must preserve accurate TypeScript inference through partial application: supplying only some parameters returns a callable for the remaining parameters, and supplying the final parameters produces the original function’s return type.
- Curried functions must infer correctly when used in pipeline and higher-order callback contexts such as `map`, including the usages shown above.
