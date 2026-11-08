Ternary expressions without true fork work in PHP Twig, fail in twig.js
`php -r "require_once './vendor/autoload.php'; \$loader = new \Twig\Loader\ArrayLoader(['index' => '{{myvar ? : 0}}']); \$twig = new \Twig\Environment(\$loader); echo \$twig->render('index', ['myvar' => FALSE]);"`

This outputs "0".

`node -e 'const Twig = require("twig"); console.log(Twig.twig({data: "{{ myvar ? : 0 }}"}).render({myvar: false}))'`

This outputs

Error compiling twig template undefined:
TwigException: Twig.expression.type.operator.binary cannot follow a Twig.expression.type.operator.binary at template:6 near ':...'

I'm not sure that ternary expressions of the form `myvar ? : "falsy output"` are a good idea, but real Twig supports them, so this library really ought to as well.
