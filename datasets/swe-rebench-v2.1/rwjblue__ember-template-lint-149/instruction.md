Disallow inline 'style' attribute in html or hbs
Im most projects, we recommend that using css to style the dom elements. But some ones may prefer to write inline style rules, because it's just quick! I would be wonderful if we have a rule that totally disallow inline style rules.

``` css
<div class="navbar" style="margin-bottom: 10px; border: 0;">
...
</div>
```

And it would be even more wonderful if we can add inline directive comment to disable a rule for some rare reasons. I'm not sure if currently we support that.

``` hbs
{{!-- template-lint bare-strings:false --}}
```

### Additional contract requirements

Expose this rule under the configuration name `inline-styles`. When enabled, it reports elements with an inline `style` attribute, and an inline directive comment can disable it. Elements without a `style` attribute are not reported.
