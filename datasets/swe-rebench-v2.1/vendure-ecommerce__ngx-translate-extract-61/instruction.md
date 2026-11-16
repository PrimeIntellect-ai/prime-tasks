Translations are not extracted from routes declaration
Hello,

When declaring routes with a title resolver ([angular documentation](https://angular.dev/guide/routing/common-router-tasks#setting-the-page-title)), it seems translations are not extracted from the resolver function.
```typescript
export const ROUTES: Route[] = [
    {
        path: '',
        loadComponent: () => import('...').then(m => m.Component),
        title: (): string => {
            const translateService = inject(TranslateService);
            return translateService.instant('page.title');  // <-- not extracted
        }
    }
];
```

It looks like prior works has been done in https://github.com/vendure-ecommerce/ngx-translate-extract/issues/44 but it seems to be limited to direct function declarations, such as
```typescript
export const errorInterceptor: HttpInterceptorFn = (req, next): any => {
    const translateService = inject(TranslateService);

    translateService.instant('translation.key').join(', '); // <-- extracted since 44 has been fixed
};
```

Do you think it is feasible to support the former case?

As a workaround, I'm using the marker `_` newly added in `ngx-translate@v16` (thank you for the recent work on its support)
```typescript
import { _, TranslateService } from '@ngx-translate/core';

export const ROUTES: Route[] = [
    {
        path: '',
        loadComponent: () => import('...').then(m => m.Component),
        title: (): string => {
            const translateService = inject(TranslateService);
            return translateService.instant(_('page.title'));
        }
    }
];
```

Thank you in advance!
