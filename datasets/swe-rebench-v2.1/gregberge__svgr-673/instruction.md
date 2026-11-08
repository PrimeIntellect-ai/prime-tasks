React does not recognize the `maskType` prop on a DOM element
<!-- Love SVGR? Please consider supporting our collective: 👉  https://opencollective.com/svgr/donate -->

## 🐛 Bug Report

*Warning: React does not recognize the `maskType` prop on a DOM element. If you intentionally want it to appear in the DOM as a custom attribute, spell it as lowercase `masktype` instead. If you accidentally passed it from a parent component, remove it from the DOM element.*

![image](https://user-images.githubusercontent.com/9919760/144318660-b513561e-ec81-4821-a24d-44f919043211.png)


I believe this change made this bug appear: https://github.com/gregberge/svgr/pull/621

## To Reproduce

I'm sorry but don't know how to demonstrate this bug as we speak. I have a React UI lib where I bundle with Rollup and use it in `Create React App(CRA)`.

// EDIT: [codesandbox.io/s/react-does-not-recognize-the-masktype-6r344](https://codesandbox.io/s/react-does-not-recognize-the-masktype-6r344)

Using:
```
My UI Lib:
"rollup": "^2.60.2"
"@svgr/rollup": "^6.0.0"

// with the config
svgr({
 ref: true,
 titleProp: true,
 svgo: false,
})

-----------------------
App (CRA):
"react": "^17.0.2"
"react-dom": "^17.0.2"
"react-scripts": "4.0.3"
"my-ui-lib": "x"
```

### Additional contract requirements

- When transforming an SVG `mask-type` attribute, preserve its hyphenated name (`mask-type`) in the generated JSX rather than emitting it as the React-unrecognized `maskType` prop.
