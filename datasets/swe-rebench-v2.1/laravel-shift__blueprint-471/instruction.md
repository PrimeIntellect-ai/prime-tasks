[Proposal] Support fully-qualified class names in relationships
First of all: 100% willing to create a complete PR for this, with tests and docs. Just saying 😀

### Synopsis:

When creating Models with relations, we found it's impossible to reference existing models that are in different directories than the configured one (`app` or `app\Models`, whatever):

You can do:
```yaml
models:
  Post:
    title: string:400
    published_at: timestamp nullable
    relationships:
      hasMany: Comment
      belongsToMany: Media, Site
```

But you _can't_ do:
```diff
models:
  Post:
    title: string:400
    published_at: timestamp nullable
    relationships:
-     hasMany: Comment
+     hasMany: Spatie\Comments\Models\Comment
      belongsToMany: Media, Site
```

because the generated relationship will then point to `App\Models\Spatie\Comments\Models\Comment`, which is not what you want...

The problem happens:
- when you want to point a relationship to a model from a third-party package;
- when you have models both inside `app` and inside `app\Models` (eg. `app\User`, but everything else in `app\Models`);
- when you're doing domain-driven development and your models live in `app\Domains\Store\Models\Comment`;

What the dev has to do in this case is:
- generate the model like this, with the wrong relationship;
- manually edit the file to point to the correct class;

Which is... fine, I guess. But I think Blueprint can do better, and we may have an intuitive syntax for it! 😀🤞

### Proposed Syntax:

The _root cause_ we identified is that the developer has no way to tell Blueprint "_I know what I'm doing. Link to this specific class, don't make any assumptions about the namespace_". And the solution we found would be for **Blueprint to also support _fully qualified namespaces_**, as a way to get around the configuration. A simple way to do that would be to... 🥁🥁🥁... **prefix the classname with a backslash**:
- `Comment` means using assumptions, so it'll use `App\Comment` or `App\Models\Comment` depending on the configuration file;
- `\Spatie\Comments\Models\Comment` means I know the _exact_ namespace of my related model, so use that one, no assumptions;

### Expected Behavior:

No change in the examples above. They still generate the same thing.

But this would also work:

```diff
models:
  Post:
    title: string:400
    published_at: timestamp nullable
    relationships:
-     hasMany: Comment
+     hasMany: \Spatie\Comments\Models\Comment
      belongsToMany: Media, Site
```

And the relationship will point to `\Spatie\Comments\Models\Comment::class`, not `App\Models\Spatie\Comments\Models\Comment`.

----

Right now this is the only place we needed the change (relationships), so that's what we've worked to solve. But if you like the `\` syntax... I think we can expand on it in the future, add support for fully-qualified-classnames for Models, Controllers, etc.

@jasonmccreary - **please let me know if you like the `\` syntax. And if you're willing to merge this in the current Blueprint version if we submit a proper PR. Do we have a green light to work on this? Yellow? Red?** 😀 Thanks 🙏

PS. We have a working prototype that we can polish, we'll submit quality PRs, tests, docs - so we'll make it easy for you to merge as a non-breaking change. You don't like something, you ask us to refactor/change, np. We can also promise to maintain that bit of code in the future, for years. But. I totally understand if you don't want Blueprint to support this at all - I'm no stranger to feature creep 🙄 I think this is something worth having, you might not...
