Prop overrides should accept a function
Currently, you can pass a function into `style` and `component` overrides but not props. For example:

<Component overrides={{  props: { 'data-test': 'foo' } }} />

works but

<Component overrides={{  props: props => ({ 'data-test': 'foo' }) }} />

doesn't.

This makes it inconsistent with `style` and `component` overrides and prevents some use-cases like adding BEM class names for different internal states of the component.

### Additional contract requirements

When override layers are combined, props supplied as functions must compose with props supplied as objects or other functions. The combined props retain values from each layer, and conflicting values from a later/source layer take precedence.
