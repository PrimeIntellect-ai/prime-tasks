Issue Setting Element Properties
## Type of Change
Enhancement/Bug

## Summary
First of all, I just want to say what you're doing here is fantastic... this is awesome! I've got wcc working with SSR for completely native web components, using a custom renderer or lit-ssr, both with working client-side hydration.

My main issue is when setting properties using a custom renderer or lit-html's render (not LitElement) with template literals, element properties in rendered templates aren't passed down to child elements. This happens with both the light dom and shadow dom.

## Why is it happening?

I'm sure I'm missing a lot here, but I think this is happening because wcc is using .innerHTML instead of .appendChild/.childNodes when adding/retrieving child nodes which causes all element properties to be discarded. I notice the dom-shim for appendChild also uses innerHTML. Is there a way to shim appendChild that retains the element's properties? This is just a guess, but I believe that by using appendChild/childNodes with a true appendChild shim instead of innerHTML, you can retain all of the properties set by renderers like lit-ssr or custom renderers like the one below. It looks like with parse 5, you can just use childNodes.push to append children. Additionally, I put some chatGPT generated shims for appendChild, removeChild, etc. at the bottom of this request in case it's any help.

**This would be huge for web components because you could SSR or SSG entire intricate render templates, passing down complex objects, maps, sets, etc. to child components, rendering the initial state on the server, without setting dozens of attributes. This would allow for creating really interesting, reusable light dom and shadow dom web component systems that allow for a complex initial render that can be cached for performance but that become deeply reactive when the client side renderer hydrates the templates. It also makes the idea of complex, _isomorphic_, vanilla web components a reality which may seem impossible otherwise.**

Studying the wcc codebase, I'm sure this goes deeper than I understand but man, this would be really powerful. I'm hoping you can fill in the gaps and see a way to make this happen!

## Details
Here is a custom ssr renderer I'm using (with everything not related to this issue removed) but this can be tested with lit-ssr's render as well:

```javascript
import { parse } from 'node-html-parser';

const isFalsy = (str) => ['false', 'null', 'undefined', '0', '-0', 'NaN', '0n', '-0n'].includes(str);

export const render = (content, container, deps) => {
  const parsedContent = parse(content());
  const elements = parsedContent.getElementsByTagName('*');

  elements.forEach((element) => {
    const attributes = element.attributes;

    Object.entries(attributes).forEach(([attribute, value]) => {
      if (attribute.startsWith('.')) {
        const propName = attribute.substring(1);
        element.removeAttribute(attribute);
        element[propName] = deps?.[value] ?? value;
      }
    });
  });

  // This is using the wcc appendChild shim which I'm sure is part of the
  // problem here since it just uses innerHTML
  if (container.shadowRoot) {
    const template = document.createElement('template');
    template.appendChild(parsedContent);
    container.shadowRoot.appendChild(template.content.cloneNode(true));
  } else {
    container.appendChild(parsedContent);
  }
};
```

Example components:

```javascript
customElements.define(
  'parent-element',
  class extends HTMLElement {
    connectedCallback() {
      const item = { message: 'Hello World' };
      this.test = 'This works';
      render(() => `<child-element .message="${item.message}"></child-element><p>${this.test}</p>`, this);
    }
  }
);

customElements.define(
  'child-element',
  class extends HTMLElement {
    connectedCallback() {
      render(() => `<p>${this.message}</p>`, this);
    }
  }
);

```

Here's how this renderer works passing down an object. Again, this doesn't work server side with wcc, but works once hydration kicks in:

```javascript
customElements.define(
  'parent-element',
  class extends HTMLElement {
    connectedCallback() {
      const item = { message: 'Hello World' };
      this.test = 'This works';
      render(() => `<child-element .item="item"></child-element><p>${this.test}</p>`, this, { item });
    }
  }
);

customElements.define(
  'child-element',
  class extends HTMLElement {
    connectedCallback() {
      render(() => `<p>${this.item?.message}</p>`, this);
    }
  }
);
```

## What do I expect?

I would expect the paragraph tag to display "Hello World" on the server side render in both scenarios. The console.log in the render function shows that the element's message property is successfully being set server side.


## What actually happens?

The paragraph element in child-element displays "undefined"

With the above components, "This works" does render server side with wcc which shows that element properties are renderable, they're just being lost somewhere when being passed to child elements.

Once the client renderer kicks in and the component is hydrated, things display as you would expect ("Hello World").

What are your thoughts? Thank you in advance!

## Some chatGPT shims
Btw, here are some quick chatGPT shims for parentNode, childNodes, appendChild, and removeChild if it's any help:

```javascript
// parentNode shim
if (!Element.prototype.parentNode) {
  Object.defineProperty(Element.prototype, 'parentNode', {
    get: function () {
      return this._parentNode || null;
    },
    set: function (newParent) {
      this._parentNode = newParent;
    },
    configurable: true
  });
}

// childNodes shim
if (!Element.prototype.childNodes) {
  Object.defineProperty(Element.prototype, 'childNodes', {
    get: function () {
      this._childNodes = this._childNodes || [];
      return this._childNodes;
    },
    configurable: true
  });
}

// appendChild shim
if (!Element.prototype.appendChild) {
  Element.prototype.appendChild = function (child) {
    if (child.parentNode) {
      child.parentNode.removeChild(child); // Remove from current parent
    }

    // Ensure childNodes exists
    this.childNodes = this.childNodes || [];

    // Add child to childNodes array
    this.childNodes.push(child);

    // Update the child's parentNode
    child.parentNode = this;

    return child;
  };
}

// removeChild shim
if (!Element.prototype.removeChild) {
  Element.prototype.removeChild = function (child) {
    if (!this.childNodes || !this.childNodes.length) return null;

    const index = this.childNodes.indexOf(child);
    if (index === -1) return null;

    // Remove the child from the array
    this.childNodes.splice(index, 1);

    // Clear the child's parentNode reference
    child.parentNode = null;

    return child;
  };
}
```
