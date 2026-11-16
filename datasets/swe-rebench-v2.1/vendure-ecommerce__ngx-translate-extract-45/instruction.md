Cast with <> in Typescript breaks marker function parsing
Hi, thanks for your fork!

I recently migrated from https://github.com/bartholomej/ngx-translate-extract to your fork as part of an Angular17 migration. We have a relatively large Angular application with ~250 components and around 1500 strings in two languages - a good test case :)

When testing the string extraction (with the marker func) I noticed that some strings were suddenly missing. I tracked down the problem and created a small repro. sample (see Angular component below).

There is a problem with parsing this line from the example component below

`const myNiceVar2 = <string>input;`

The cast interrupts the parsing of further markers in the current function.

```typescript
import { Component } from '@angular/core';
import { marker } from '@colsen1991/ngx-translate-extract-marker';

marker('1');

@Component({
  standalone: true,
  imports: [],
  selector: 'app-root',
  template: '<h1>hello</h1>',
  styles: '',
})
export class AppComponent {
  constructor() {
    marker('2');
  }

  myFunc(): void {
    marker('3');
    const input: unknown = 'hello';
    const myNiceVar1 = input as string;
    marker('4');

    // --> cast in the next line breaks the parsing in this block
    const myNiceVar2 = <string>input;
    marker('5_i_will_never_show');
  }

  myOtherFunc(): void {
    marker('6');
  }
}
```

leads to this output

```JSON
{
	"1": "1",
	"2": "2",
	"3": "3",
	"4": "4",
	"6": "6"
}
```

We can easily get round this and there were only a few places in our code. But I think it should be fixed somehow, so I'm posting it here as an issue.
