TranslateService used as an injected const does not work in a const method (like HttpInterceptorFn)
A fix was done for readonly inject earlier in version 9.1.1. Additionally somewhat related support is required for cases like ResolveFn, HttpInterceptorFn,... which are const's rather than classes.

In ng14 or something the following syntax
`@Injectable()
export class ErrorToastInterceptor implements HttpInterceptor {`
was (optionally) changed to
`export const errorToastInterceptor: HttpInterceptorFn = (req: HttpRequest<unknown>, next: HttpHandlerFn) => {`

Where the TranslationService is injected as a const, like:
`const translateService = inject(TranslateService);`

`translateService.instant('KEY_NAME')` is unfortunately not picked up :( [HIDDEN]

Thanks for looking into it!

### Additional contract requirements

- Extract literal translation keys passed to TranslateService methods when the service is injected within a function-valued const declaration.
- Calls to a TranslateService method whose key argument is supplied as a runtime value rather than a literal must not contribute an extracted key.
