dxDataGrid: Uncaught TypeError: Cannot read property 'beforeDestroy' of undefined
### Issue Type

[x] 'bug report'

### Description

#### Current Behavior

If you start up the examples (npm run serve), ungroup the region column in the dxDataGrid Example you'll get the following javascript error:

Uncaught TypeError: Cannot read property 'beforeDestroy' of undefined
    at callHook (vue.esm.js:2917)
    at HTMLDivElement.Vue.$destroy (vue.esm.js:2700)
    at HTMLDivElement.oneTimeHandler (events_engine.js:372)
    at callHandler (events_engine.js:117)
    at Object.wrappedHandler (events_engine.js:140)
    at handleCallback (events_engine.js:211)
    at Array.forEach (<anonymous>)
    at Object.callHandlers (events_engine.js:215)
    at events_engine.js:413
    at Object.<anonymous> (events_engine.js:281)

#### Expected Behavior

No error

### Steps to Reproduce

- npm run serve
- navigate to dxDataGrid example
- ungroup column region

(or click on page 2 - same error)

### Environment Details

- master as of 036025c9aa5129c34cc4f446bdbc89d8e6a34ede
- chrome 65.0.3325.181
