TypeError: selector.includes is not a function when using tippy.js
First of all, great work on this library! I've attempted to migrate tests in my project from jsdom to happy-dom and I was stunned by the results. Some tests seen over 20x improvement in performance!

However, I am running into some issues, and I am happy to help resolve them in some pull request, but first I'd like to understand if this should be fixed in happy-dom or some other place. Maybe you already have this on your radar.

I am using `tippy.js` (or - React version of it) and I have this error:
```
TypeError: selector.includes is not a function
 ❯ Function.getSelectorParts node_modules/happy-dom/lib/query-selector/QuerySelector.js:133:44
 ❯ Function.querySelectorAll node_modules/happy-dom/lib/query-selector/QuerySelector.js:27:34
 ❯ HTMLDocument.querySelectorAll node_modules/happy-dom/lib/nodes/document/Document.js:266:40
 ❯ getArrayOfElements node_modules/tippy.js/dist/tippy.cjs.js:127:29
 ❯ tippy node_modules/tippy.js/dist/tippy.cjs.js:1595:18
 ❯ node_modules/@tippyjs/react/dist/tippy-react.umd.js:256:24
    254|         }
    255|
    256|         var instance = tippy(element || mutableBox.ref || ssrSafeCreateDiv(), Object.a…
       |                        ^
    257|           plugins: [classNamePlugin].concat(props.plugins || [])
    258|         }));
 ❯ commitHookEffectListMount node_modules/react-dom/cjs/react-dom.development.js:20573:26
 ❯ commitLifeCycles node_modules/react-dom/cjs/react-dom.development.js:20634:11
 ❯ commitLayoutEffects node_modules/react-dom/cjs/react-dom.development.js:23426:7
 ❯ HTMLUnknownElement.callCallback node_modules/react-dom/cjs/react-dom.development.js:3945:14
```

I have a CodeSandbox that recreates this issue here: https://codesandbox.io/s/happy-dom-tippy-test-forked-54v9tg?file=/src/App.test.tsx

As far as I see, the problem happens in this function of tippy.js: https://github.com/atomiks/tippyjs/blob/ad85f6feb79cf6c5853c43bf1b2a50c4fa98e7a1/src/dom-utils.ts#L25
And it might seem to be an issue in this library, but it works fine in jsdom. It seems like in jsdom, the first `if` of this function, so:
```
 if (isElement(value)) {
    return [value];
  }
```
is resolving to true, but it is not when using happy-dom. As a result happy-dom code is then called for `querySelectorAll`, but the selector is not a string, so the call to `includes` fails of course.

In the end, on tippy side, this code is being executed to verify the type of the element: https://github.com/atomiks/tippyjs/blob/ad85f6feb79cf6c5853c43bf1b2a50c4fa98e7a1/src/utils.ts#L29 and calling `toString` using jsdom gives this result: `[object HTMLButtonElement]`, but in happy-dom it's just `[object Object]`.

I assume it might be related to this list of non implemented element classes (https://github.com/capricorn86/happy-dom/blob/117595ed2f7d30d7e99757aafb316ab309b86bfc/packages/happy-dom/src/config/NonImplemenetedElementClasses.ts) and adding the `Button` type should fix that, right?
