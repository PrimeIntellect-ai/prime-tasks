Rule Proposal: Require "shouldComponentUpdate" or PureRenderMixin to be applied
On our team, we want to ensure all components are optimized. This means either PureRenderMixin must be applied on the component, or the component must have a `shouldComponentUpdate` method defined. It would be great if ESLint could warn developers when they have forgotten to optimize.

### Additional contract requirements

- The rule is exposed by the plugin under the public name `require-optimization`, i.e. `require('eslint-plugin-react').rules['require-optimization']` resolves to the rule implementation.
