Be Able to Configure Rules
__Is your feature request related to a problem? Please describe__

Rules cannot be configured at the moment. In [eslint](https://eslint.org/docs/developer-guide/working-with-rules#the-context-object) this is possible allowing for the reuse of configurable rules.


__Describe the solution you'd like__

<!-- A clear and concise description of what you want to happen. -->

An example of a configuration:

```javascript
module.exports = {
  configs: {
    'foo': {
      rules: {
        'bar': [ 'error', {
          types: [ 'bpmn:ServiceTask' ]
        } ]
      }
    }
  }
};
```

__Describe alternatives you've considered__

<!-- A clear and concise description of any alternative solutions or features you've considered. -->
Alternatively, rules with different configurations can be created as separate files. However, this would not be my preferred solution.
