[ember-intl] '.ds-store' is not a valid locale name
I've been using ember-intl in my main application and a number of addons. During the build process, I've noticed the following warning.

    [ember-intl] '.ds-store' is not a valid locale name

I believe it is taking the *.DS_Store* file produced by Macs and trying to think of it as a translation file. I only noticed this issue once adding translations to addons that are consumed by my application. The file is likely converted to *.ds-store* when the broccoli TranslationReducer plugin normalizes the file names.

I have a *.DS_Store* entry in my global *.gitignore* file, but I don't have it in my *.npmignore* files, which I'm guessing is where it is finding that file. However, should it be necessary to include that entry in the *.npmignore* or should this be something that ember-intl accounts for?

### Environment

- Ember Version: 3.1.4
- Ember CLI Version: 3.1.4
- Ember Intl Version: 3.0.0
- Browser(s): Any
- Node Version: 8.11.3

### Additional contract requirements

- Provide a public function `validLocaleFile(filename)` in module `lib/utils/valid-locale-file.js`. It returns `true` when `filename` is a string whose extension is `.json`, `.yaml`, or `.yml`, and returns `false` otherwise, including when `filename` is not a string.
- During a build, files whose extension is not one of `.json`, `.yaml`, or `.yml` (for example a `.DS_Store` artifact) must not be treated as locale translation files and must not produce an invalid-locale warning.
