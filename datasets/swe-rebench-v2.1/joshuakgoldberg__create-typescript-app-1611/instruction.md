⚡️ Performance: Run pnpm dedupe in --offline mode during setup
## Overview

Splitting out of #860: per https://github.com/pnpm/pnpm/issues/6619#issuecomment-1968418251, `pnpm dedupe --offline` is quite a bit faster than the non-`--offline` version. I tried this out locally with `hyperfine` and it went from `4.013 s` to `2.016 s` mean. Nice! ⚡
