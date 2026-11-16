Incorrect key mapping in twig arrays with integer keys
Hi!

I encountered an issue where twig modifdy some numeric keys in an associative array defined in my template.

### How to reproduce

In my template:

```twig
{% set trad = {194:'ABC',141:'DEF',100:'GHI',170:'JKL',110:'MNO',111:'PQR'} %}
{% set trad2 = {'194':'ABC','141':'DEF','100':'GHI','170':'JKL','110':'MNO','111':'PQR'} %}
{% dump({trad: trad, trad2: trad2}) %}
```

Expected output:

```php
array:2 [▼
  "trad" => array:6 [▼
    194 => "ABC"
    141 => "DEF"
    100 => "GHI"
    170 => "JKL"
    110 => "MNO"
    111 => "PQR"
  ]
  "trad2" => array:6 [▼
    194 => "ABC"
    141 => "DEF"
    100 => "GHI"
    170 => "JKL"
    110 => "MNO"
    111 => "PQR"
  ]
]
```

Real output:

```php
array:2 [▼
  "trad" => array:6 [▼
    194 => "ABC"
    141 => "DEF"
    100 => "GHI"
    170 => "JKL"
    110 => "MNO"
    195 => "PQR" // The key 111 is changed to 195 ¯\_(ツ)_/¯
  ]
  "trad2" => array:6 [▼
    194 => "ABC"
    141 => "DEF"
    100 => "GHI"
    170 => "JKL"
    110 => "MNO"
    111 => "PQR" // When the keys are explicitly defined as strings, they remain correct
                 // ... as integer... not following the PHP logical... but why not
                 // === EDIT === Sorry, this is "ok", PHP does that.
  ]
]
```

### Expected Behavior

Numeric keys should remain unchanged and not be altered by Twig when converted to PHP arrays. => this is the issue

String keys maybe should keep they type when converted to PHP arrays ? => this is a simple question ^^,

### Environment

* Twig versions: at least 3.15, still in 3.19
* PHP version: 8.3.14
* Framework : Symfony 6.4
