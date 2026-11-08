ember/no-classic-components fails on imports from `@ember/component`
The `ember/no-classic-components` rule fails on this code, and it probably shouldn't?

```
import { setComponentTemplate } from '@ember/component';
```
