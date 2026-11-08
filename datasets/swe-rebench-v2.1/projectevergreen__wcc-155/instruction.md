Light DOM children / slots (aka HTML Web Components)
## Summary

Although primarily a client side / runtime dependent technique, the idea of [HTML Web Components](https://blog.jim-nielsen.com/2023/html-web-components-an-example/), seems like a really nice technique to be able to do in situations where it would be easer to "slot" children in via HTML instead of attributes, in particular for very content heavy scenarios and that could still be done at SSR time.

For comparison
```html
<!-- Attributes -->
<app-card
  heading="My Heading"
  image="/path/to/some/image.webp"
/></app-card>

<!-- Light DOM Children -->
<app-card>
  <h1>My Heading</h1>
  <img src="/path/to/some/image.webp""/>
</app-card>
```

## Details

Now this basically relies on doing an `innerHTML` in the `connectedCallback` function, e.g.
```js
export class Card extends HTMLElement {
  connectedCallback() {
    this.innerHTML = `
      <div class="card">
        ${this.innerHTML}
      </div>
    `
  }
}
```

but if done on the server, could basically allow for any sort of option for handling light DOM children that is still standard compliant, especially in conjunction with something like https://github.com/ProjectEvergreen/greenwood/issues/1233

----

I've tested this in the browser and so as long as this doesn't break any test cases, this _seems_ like a legit feature to support?

### Additional contract requirements

- An `<img>` supplied as light-DOM content of a custom element is serialized as `<img src="https://www.greenwoodjs.io/assets/greenwood-logo-og.png" alt="Greenwood logo">`, without a trailing slash.
- Server-side rendering must preserve light-DOM child content supplied inside custom elements in the serialized output, including content supplied by nested custom elements.
