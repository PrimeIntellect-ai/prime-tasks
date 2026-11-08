Add eslint-plugin-qunit to blueprint
Have we ever considered adding/enabling [eslint-plugin-qunit](https://github.com/platinumazure/eslint-plugin-qunit) linting to the Ember blueprints? It's a great plugin for enforcing QUnit best practices in tests, and I consider it to be the most useful/relevant linting plugin that we haven't added to the blueprint yet. I use in many of my Ember apps/addons.

RFC: https://github.com/emberjs/rfcs/pull/702 (similar to the recent [prettier RFC](https://github.com/emberjs/rfcs/blob/master/text/0628-prettier.md)).

CC: @platinumazure

### Additional contract requirements

- Blueprint-generated applications and addons include `eslint-plugin-qunit` in their package manifests using a compatible version.
- Blueprint-generated test files receive `eslint-plugin-qunit` linting.
