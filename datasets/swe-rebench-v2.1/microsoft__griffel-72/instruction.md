react: Better support for React 18
RC for React 18 is already published:

![image](https://user-images.githubusercontent.com/14183168/154933630-e23a7ce7-04ee-488e-a130-8637249bd890.png)

---

> **NOTE: Make sure you read the section "When to Insert <style> on The Client". If you currently inject style rules "during render", it could make your library VERY slow in concurrent rendering.**
> https://github.com/reactwg/react-18/discussions/110

In short we should use `useInsertionEffect` to apply our styles to DOM.

For reference:
- changes in Emotion https://github.com/emotion-js/emotion/pull/2600
- issue with bundling https://github.com/emotion-js/emotion/pull/2651

- [x] Types in React 18 does not allow `children` by default in `React.FC`, check components and update (#214)
