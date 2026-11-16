Application translations DOES NOT override addon translations
- [x] I am on the [latest](https://github.com/ember-intl/ember-intl/releases/latest) ember-intl version
- [x] I have searched the [issues](https://github.com/ember-intl/ember-intl/issues) of this repo and believe that this is not a duplicate

### Environment

- Ember Version: 3.12.1
- Ember CLI Version: 3.12.0
- Ember Intl Version: 4.2.0
- Browser(s): Chrome
- Node Version: v10.16.3

### Steps to Reproduce

- Create an empty app, add `ember-intl` add-on
- Create 2 empty add-on, called "aaaa" & the other "zzzz"
- Add `ember-intl` in the 2 add-ons
- Create a translation called "aaaa_translation" in `translations/en-us.yaml` of "aaaa" add-on
- Create a translation called "zzzz_translation" in `translations/en-us.yaml` of "zzzz" add-on
- `yarn/npm link` the add-ons with the app & add it in `package.json` of the application
- Override "aaaa_translation" & "zzzz_translation" in in `translations/en-us.yaml` of the application
- `ember serve` ...

![image](https://user-images.githubusercontent.com/13900970/69610609-740f8100-102c-11ea-9598-75afe9d1091f.png)


It seems that the translations files are not correctly merged. Here a dump of `listFiles` from the `reduce` function in `lib/broccoli/translation-reducer/index.js` :
```
[ '/tmp/broccoli-54539WABk1c5bWG3/out-229-funnel/aaaa/en-us.yaml',
  '/tmp/broccoli-54539WABk1c5bWG3/out-229-funnel/en-us.yaml',
  '/tmp/broccoli-54539WABk1c5bWG3/out-229-funnel/fr-fr.yaml',
  '/tmp/broccoli-54539WABk1c5bWG3/out-229-funnel/zzzz/en-us.yaml' ]
```

`en-us.yaml` from "zzzz" add-on always override the `en-us.yaml` from application.

### Additional contract requirements

When application and add-on translations are merged, the application value takes precedence for a key defined by both. Add-on translation entries whose keys are not defined by the application remain available in the merged output.
