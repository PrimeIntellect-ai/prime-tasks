🚀 Feature: Add ignoreDeps Addon to blockRenovate
### Feature Request Checklist

- [x] I have pulled the latest `main` branch of the repository.
- [x] I have [searched for related issues](https://github.com/JoshuaKGoldberg/create-typescript-app/issues?q=is%3Aissue) and found none that matched my issue.

### Overview

To support #2177 (https://github.com/JoshuaKGoldberg/create-typescript-app/issues/2177#issuecomment-2787002777), I'm going to pin `all-contributors-cli` to a specific version. That means this repo's own `.github/renovate.json` is going to need an `ignoreDeps` Addon.

### Additional Info

I'll also add an `intake` to read it from disk if available.

### Additional contract requirements

- Commands that run the All Contributors CLI must invoke `pnpx all-contributors-cli@6.23.0 add`.
