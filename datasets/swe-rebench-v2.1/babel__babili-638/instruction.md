minify-simplify produces invalid code (duplicate symbols)
Hello,

There is a clash when the same symbol exists in the parent and the `else` scopes like in this example (look for the `clash` functions):

#### Input Code

```sh
babel --plugins minify-simplify test.js > simplify.js
```

```js
function test (a) {
  const clash = () => {
    return 'tata';
  };

  if (a) {
    return clash ();
  } else {
    const clash = () => {
      return 'toto';
    };

    return clash ();
  }
}

console.log (test ());
console.log (test (true));
```

#### Actual Output
```sh
simplify.js:10
  };
  ^
SyntaxError: Identifier 'clash' has already been declared
    at createScript (vm.js:56:10)
    at Object.runInThisContext (vm.js:97:10)
    at Module._compile (module.js:542:28)
    at Object.Module._extensions..js (module.js:579:10)
    at Module.load (module.js:487:32)
    at tryModuleLoad (module.js:446:12)
    at Function.Module._load (module.js:438:3)
    at Module.runMain (module.js:604:10)
    at run (bootstrap_node.js:389:7)
    at startup (bootstrap_node.js:149:9)
```

```js
function test(a) {
  const clash = () => {
    return 'tata';
  };

  if (a) return clash();

  const clash = () => {
    return 'toto';
  };

  return clash();
}

console.log(test()), console.log(test(true));
```

#### Expected Output (or similar)

```js
function test(a) {
  const clash = () => {
    return 'tata';
  };

  if (a) return clash();

  {
    const clash = () => {
      return 'toto';
    };

    return clash();
  }
}

console.log(test()), console.log(test(true));
```

```
toto
tata
```

### Additional contract requirements

- Preserve the reported program's branch-specific behavior: calling `test()` yields `toto`, and calling `test(true)` yields `tata`.
