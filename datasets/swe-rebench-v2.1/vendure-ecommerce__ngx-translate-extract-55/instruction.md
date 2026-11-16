Service parser is not locating the TranslateService if it is a private field
The service parser fails to extract translation keys when the `TranslateService` is assigned to a private field using the JavaScript private field syntax (#). For example, from the code below the key 'hello.world' is not extracted:

```ts
import {Component, inject} from '@angular/core';
import {TranslateService} from '@ngx-translate/core';

@Component({
  selector: 'my-component',
  template: `<p>{{ translatedText }}</p>`
})
export class MyComponent {
  readonly #translate = inject(TranslateService);
  translatedText = '';

  constructor() {
    this.translatedText = this.#translate.instant('hello.world');
  }
}

```
