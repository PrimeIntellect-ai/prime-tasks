🐛 Bug: Transition mode is moving an existing All Contributors badge outside of badges
### Bug Report Checklist

- [x] I have tried restarting my IDE and the issue persists.
- [x] I have pulled the latest `main` branch of the repository.
- [x] I have [searched for related issues](https://github.com/JoshuaKGoldberg/create-typescript-app/issues?q=is%3Aissue) and found none that matched my issue.

### Expected

Running `npx create-typescript-app` in a repository templated from an older version of the tooling should migrate all README.md badges over to the new template.

### Actual

https://github.com/JoshuaKGoldberg/cached-factory/pull/21 -> https://github.com/JoshuaKGoldberg/cached-factory/blob/71fac31de038ab6208f779afe5abe7bc34518f69/README.md?plain=1#L21 shows:

```md
</p>

<img align="right" alt="All Contributors: 1" src="<https://img.shields.io/badge/all_contributors-1-21bb42.svg>" ">

## Usage
```

That's an odd image and definitely a bug.

### Additional Info

The image on `main` is: https://github.com/JoshuaKGoldberg/cached-factory/blob/30ce74b3761cd0f9f5c7612b5a9ef9aaaf26e687/README.md?plain=1#L9C1-L9C99

```md
<!-- ALL-CONTRIBUTORS-BADGE:START - Do not remove or modify this section -->
<img alt="All Contributors: 1" src="https://img.shields.io/badge/all_contributors-1-21bb42.svg" />
<!-- ALL-CONTRIBUTORS-BADGE:END -->
```

🎁

### Additional contract requirements

During migration, existing README badges must remain in the generated template's badge collection. In particular, an All Contributors badge must not be emitted separately as the project logo.
