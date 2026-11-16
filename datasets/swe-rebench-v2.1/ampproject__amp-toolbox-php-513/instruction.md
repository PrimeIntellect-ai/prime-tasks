`SelfClosingSVGElements` document filter erroneously self-closes `g` tags
As reported in a AMP plugin [support forum topic](https://wordpress.org/support/topic/svg-group-tag-is-broken/), given this input HTML:

```html
<svg>
  <g id="ok">
    <path/>
  </g>
</svg>
```

The output is:

```html
<svg>
  <g id="ok"/>
    <path/>
</svg>
```

[HIDDEN]

https://github.com/ampproject/amp-toolbox-php/blob/4cecbc5953823f15c2f9ea22ec3ee947040c1547/src/Dom/Document/Filter/SelfClosingSVGElements.php#L21-L25

### Additional contract requirements

- For the reported SVG input, keep the `<g>` element open around its `<path>` child, and serialize its closing `</g>` after the child.
