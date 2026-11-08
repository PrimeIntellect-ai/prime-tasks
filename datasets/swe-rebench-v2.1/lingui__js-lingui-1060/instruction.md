Origins loss for second locale when formatOptions.lineNumbers is set to false
I'm using lingui version 3.8.9

In my config I have defined two locales

`"locales": ["en", "de"]`

and set formatOptions.lineNumbers to false

`"formatOptions":{"origins": true, "lineNumbers": false}`

My catalogs path is `locales/{locale}/messages`

**Describe the bug**
After I run `lingui extract` I got the following result:

My `locales/en/messages` turned from
```
#: src/App.js:10
msgid "This is a Test"
msgstr "This is a Test"
```
into
```
#: src/App.js
msgid "This is a Test"
msgstr "This is a Test"
```
(Which is fine)

But for my `de` locale the catalog `locales/de/messages` turned from
```
#: src/App.js:10
msgid "This is a Test"
msgstr "Das ist ein Test"
```
into
```
#:
msgid "This is a Test"
msgstr "Das ist ein Test"
```

As you can see, not just the line number is removed also the origin is not longer in the catalog.
If I switch the direction of the locales in the config from `"locales": ["en", "de"]` to `"locales": ["de", "en"]`
the bug effects my `locales/en/messages` and just `locales/de/messages` is fine


**Expected behavior**
With the config `"formatOptions":{"origins": true, "lineNumbers": false}`
all catalogs get rid of the lineNumbers but keep the origins.

**Additional context**
- jsLingui version 3.8.9
