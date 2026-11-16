Inconsistent {% continue %} Behavior in Snippets Between Shopify Liquid and LiquidJS
The behavior of `{% continue %}` inside snippets seems to differ between Shopify Liquid and LiquidJS. In Shopify Liquid, {% continue %} effectively acts as an "early return" from the snippet, preventing any further code in the snippet from rendering. However, in LiquidJS, `{% continue %}` behaves as it would inside a loop, causing the loop in the parent context to skip to the next iteration.

Steps to Reproduce:
1. Create a Liquid snippet (example-snippet.liquid):
```
{% continue %}
<p>This part of the snippet should be skipped</p>
```

2. Use the snippet in a layout/section with a parent loop in LiquidJS:
```
{% for i in (1..3) %}
  <p>Loop iteration: {{ i }}</p>
  {% render 'example-snippet' %}
  <p>This code will be skipped in LiquidJS, but not Shopify Liquid</p>
{% endfor %}
```

Expected Behaviour (based on Shopify Liquid):

```
<p>Loop iteration: 1</p>
<p>This code will be skipped in LiquidJS, but not Shopify Liquid</p>
<p>Loop iteration: 2</p>
<p>This code will be skipped in LiquidJS, but not Shopify Liquid</p>
<p>Loop iteration: 3</p>
<p>This code will be skipped in LiquidJS, but not Shopify Liquid</p>
 ```

 What I actually get with LiquidJS is this:

 ```
<p>Loop iteration: 1</p>
<p>Loop iteration: 2</p>
<p>Loop iteration: 3</p>
 ```

I know that this may seem like a bit of an edge case, but I've seen devs using `{% continue %}` in Snippets as an early return fairly commonly so should probably be fixed

### Additional contract requirements

- The `Liquid` constructor accepts an optional `memoryLimit` option (a number). It caps the number of bytes the engine may allocate during a render; when the cap is exceeded, rendering aborts.
- When the memory limit is exceeded, `parseAndRenderSync` and its asynchronous equivalent `parseAndRender` throw an `Error` with the message `memory alloc limit exceeded, line:1, col:1`.
