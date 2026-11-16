Add block syntax for pgettext
Follow up on #441, #1126

It was difficult to come to an agreement on the syntax for block translation with context, so it was left out of #1126. However this should still be added.

The possibilities that were discussed are:

* `context` keywords: `{% trans context "mycontext" num=3 %}One Text{% pluralize %}{{num}} Texts{% endtrans%}`
  * [This resembles what Django uses](https://docs.djangoproject.com/en/3.1/topics/i18n/translation/#translate-template-tag)
* `{% context %}` block: `{% trans %}Click me{% context %}In annoying popup{% endtrans %}` (similar to `{% pluralize %}`
  * But context is usually very short, using a block might be wasteful
* Adding on `trans` directly: `{% trans "greeting" %}Hello{% endtrans %}` or `{% trans(greeting) %}Hello{% endtrans %}`

I personally don't feel strongly at all, but I really could use such a syntax.
