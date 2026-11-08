Macro arguments using leading/tailing underscore (BC introduced in v3.15)
Hi. I discovered a side effect after upgrading to the latest version, related to [this line in PR 4391](https://github.com/twigphp/Twig/pull/4391/files#diff-60c82d266554727246bf978c6075764c0538da108886e554bb8b10fa3b21c751R88).
For me, it's a BC, which may affect others as well.
The usage of macro arguments having leading/tailing underscores worked well until 3.15.

Example:
```twig
{% macro testing(_message) %}
The message: '{{ _message }}'.
{% endmacro %}
{{ _self.testing('Hello World!') }}
```

Output:
3.14: `The message: 'Hello World!'.`
3.15: `The message: ''.`

Compiled template:
[HIDDEN]
```php
[...]
class __TwigTemplate_[...] extends Template
[...]
    // line 1
    public function macro_testing($_message = null, ...$varargs): string|Markup
    {
        $macros = $this->macros;
        $context = [
            [HIDDEN]
            "varargs" => $varargs,
        ] + $this->env->getGlobals();

        $blocks = [];

        return ('' === $tmp = \Twig\Extension\CoreExtension::captureOutput((function () use (&$context, $macros, $blocks) {
            // line 2
            yield "The message: '";
            [HIDDEN]
            yield "'.
";
            yield from [];
        })())) ? '' : new Markup($tmp, $this->env->getCharset());
    }
```

I'm curious how I should see the code change. If this is the intention, maybe a `trigger_deprecation` should be called while evaluating the macro arguments.
I just wanted to let you know - the affected templates will be fixed on my side.

### Additional contract requirements

- Macro arguments whose declared names begin or end with underscores must remain accessible inside the macro body under their exact declared names, with their supplied values rendered.
