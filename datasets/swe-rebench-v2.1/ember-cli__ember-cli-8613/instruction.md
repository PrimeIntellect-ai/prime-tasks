ember/jquery should be ^0.6.0 in 3.9.x
Trying to remove deprecation warnings from Ember 3.9.0.

And I am receiving the following deprecation:
`
Using Ember.$() has been deprecated, use import jQuery from 'jquery'; instead [deprecation id: ember-views.curly-components.jquery-element] See https://emberjs.com/deprecations/v3.x#toc_jquery-apis for more details.`

The code throwing the deprecation message is:
```
import jQuery from 'jquery';

import Component from '@ember/component';
export default Component.extend({
  ...
    _addResizableHandlers() {
        const jqueryElement = jQuery(this.element);
        jqueryElement.resizable({
            handles: 'all',
            stop: bind(this, this._onResizeEnd)
        });
        this._resizableInstance = jqueryElement.resizable('instance');
    },
  ...
});
```
and the _addResizableHandlers methods is getting transpiled to
```
_addResizableHandlers() {
      const jqueryElement = Ember.$(this.element);
      jqueryElement.resizable({
        handles: 'all',
        stop: Ember.run.bind(this, this._onResizeEnd)
      });
      this._resizableInstance = jqueryElement.resizable('instance');
    },
```

In my package.json (from the default blueprint)
```
"@ember/jquery": "^0.5.2",
```

I believe that because my yarn.lock was pointing to 0.5.2, was the cause of this transpilation because upgrading to 0.6.0, fixed the deprecation warning (and transpiled properly)

So I believe `@ember/jquery` should be `^0.6.0` for the default blueprint in 3.9.x

Posting here by suggestion from https://github.com/emberjs/ember.js/issues/17908
