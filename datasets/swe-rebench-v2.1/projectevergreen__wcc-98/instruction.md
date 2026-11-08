using template literal backticks as quotes for custom element tag name breaks rendering
## Type of Change

<!-- Delete what does not apply -->
- Bug

## Summary
Using template string \` as quotes for the tag name in `customElements.define` definition  "breaks" the compiler.
```js
customElements.define(`wcc-footer`, Footer);
```

It will come out as it came in, un-serialized in the rendered HTML
```html
<wcc-footer></wcc-footer>
```

## Details
Example
```js
const template = document.createElement('template');

template.innerHTML = `
  <footer class="footer">
    <h4>
      <a href="https://www.greenwoodjs.io/">My Blog &copy;${new Date().getFullYear()} &#9672 Built with GreenwoodJS</a>
    </h4>
  </footer>
`;

class Footer extends HTMLElement {
  connectedCallback() {
    if (!this.shadowRoot) {
      this.attachShadow({ mode: 'open' });
      this.shadowRoot.appendChild(template.content.cloneNode(true));
    }
  }
}

export default Footer;

customElements.define(`wcc-footer`, Footer);
```

----

FWIW, double quotes work fine
```js
const template = document.createElement('template');

template.innerHTML = `
  <footer class="footer">
    <h4>
      <a href="https://www.greenwoodjs.io/">My Blog &copy;${new Date().getFullYear()} &#9672 Built with GreenwoodJS</a>
    </h4>
  </footer>
`;

class Footer extends HTMLElement {
  connectedCallback() {
    if (!this.shadowRoot) {
      this.attachShadow({ mode: 'open' });
      this.shadowRoot.appendChild(template.content.cloneNode(true));
    }
  }
}

export default Footer;

customElements.define("wcc-footer", Footer);
```
