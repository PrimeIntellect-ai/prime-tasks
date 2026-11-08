Incorrect faker provider generated from column defined as "name: enum"
- Laravel Version: 11.1.1
- PHP Version: 8.3.7
- Blueprint Version: 2.10.0
- Platform: Mac

### Issue:
It's possible this is intended behavior, but feels more like a bug?

If I define a model with a column name of `name` and a type `enum`

```yaml
models:
  Post:
    name: enum:one,two,three
```

I would expect the generated factory definition to look like this
```
return [
  'name' => $this->faker->randomElement(["one","two","three"]),
];
```

but instead I get

```
return [
  'name' => $this->faker->name(),
];
```

[HIDDEN]
https://github.com/laravel-shift/blueprint/blob/4485f6b3491eaeca6c9d59114b5c1dd349f914d0/src/Generators/FactoryGenerator.php#L123


Repro:
```
composer create-project laravel/laravel example-app
cd example-app
composer require -W --dev laravel-shift/blueprint
php artisan blueprint:new
# fill in draft.yaml as above
php artisan blueprint:build
```

As a workaround I can easily change the name of the column, but as-is the generated migration ends up with `$table->enum('name', ["one","two","three"]);`, so if nothing else, the logic seems to differ a bit between the Factory and Migration generators ¯\\\_(ツ)\_/¯
