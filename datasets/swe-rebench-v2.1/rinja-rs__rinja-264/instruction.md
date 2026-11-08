Variables defined in base template, fail to be accessed in partials included by extended templates
Given the following example:
~~~~
## base.txt
{% let variable = 42 %}
{% block extended %}{% endblock %}
~~~~

~~~~
## extended.txt
{% extends "base.txt" %}
{% block extended %}
WORKS for extended: {{ variable }}
{% include "partial.txt" %}
{% endblock %}
~~~~

~~~~
## partial.txt
FAILS for extended: {{ variable }}
WORKS for includes: {{ variable }}
~~~~

~~~~
## includes.txt
{% let variable = 42 %}
WORKS for includes: {{ variable }}
{% include "partial.txt" %}
~~~~

The `extended.txt` template fails for Rinja with the following error, meanwhile succeeds with Askama (i.e. Rinja regression when migrating from Askama):
~~~~
error[E0609]: no field `variable` on type `&RinjaTestTemplate`
~~~~

Meanwhile, `includes.txt` works for both Askama and Rinja.

----

Even more strangely, if the `partial.txt` is an empty file, thus containing no reference to the variable, just by including it in `extended.txt` triggers the error.

Meanwhile, if the inclusion is missing, `extended.txt` compiles correctly.

----

For some reason the Rinja parser / generator behaves differently for variables defined in a base template, than variables defined in non-inherited templates, but only when that variable is used in partials (i.e. `{% include "partial.txt" %}`).

Thus, at least the scoping rules seem to be applied ambiguously.

Moreover, the current Rinja documentation supports the case, by implying that `{% include ... %}` statements should behave as if they wouldn't be there, and the contents of the included template would be spliced at the place of inclusion:

> The include statement lets you split large or repetitive blocks into separate template files. Included templates get full access to the context in which they're used, including local variables like those from loops:

----

Where would such a use-case be needed:
* one wants to create multiple pages, that each share a common outer layout, thus one creates a `base` template;
* the `base` template is then extended for each `extended` pages;
* the `extended` pages would like to include some common `widget` that are developed as includes (i.e. the `partial.txt` template in this issue);
* the `base` and `widget` "communicate" based on variables, but don't want to involve the `extended` pages, thus the developer defines some variables inside `base` that are to be used in `widget` templates;

At the moment, for the given use-case, I see no workaround that doesn't involve moving and duplicating the variables both in `base` and `extended`.

### Additional contract requirements

An included template must be able to resolve local variables that are available where it is included, including variables declared in a base template and inherited into an extended block. Including an empty partial in an inherited block must not, by itself, make an otherwise valid template fail to compile.
