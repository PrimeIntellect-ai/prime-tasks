gjs/gts Incorrect token mapping after handlebars
Hi there!

First I would like to say great work on this addon so far, adding `gjs-gts-parser` has enabled us to really do a lot of cool things and increase support for `gjs/gts` files in a lot of tools.

I am currently working on adding `gjs/gts` support to [SonarJS](https://github.com/SonarSource/SonarJS)
https://community.sonarsource.com/t/add-support-for-embers-new-gjs-gts-file-format-to-sonarjs/103769
And it would not be possible without this parser.

I think I have found a bug in the parser while doing this work, but I'm not sure as I'm not really an expert on custom ESLint parsers.
Basically it seems like javascript tokens that come after some handlebars tokens don't have the correct loc mapping.

Here is a test for reproduction
```
  it('correctly maps tokens after handlebars', async () => {
    const eslint = initESLint();
    const code = `
    import Component from '@glimmer/component';

    export const fakeTemplate = <template>
      <div>{{foo}}</div>
    </template>;

    export default class MyComponent extends Component {
      constructor() {
        super(...arguments);
      }

      foo = bar;
      <template>
        <div>
          some totally random, non-meaningful text {{bar}}
        </div>
      </template>
    }
    `;
    const results = await eslint.lintText(code, { filePath: 'my-component.gjs' });

    const resultErrors = results.flatMap((result) => result.messages);
    expect(resultErrors).toHaveLength(3);
    expect(resultErrors[0].message).toBe("'foo' is not defined.");
    expect(resultErrors[0].line).toBe(5);

    expect(resultErrors[1].message).toBe("'bar' is not defined.");
    expect(resultErrors[1].line).toBe(13);

    expect(resultErrors[2].message).toBe("'bar' is not defined.");
    expect(resultErrors[2].line).toBe(16);
  });
```

When we do `foo = bar;` in the test we expect the error to be on line 13, but if you run the actual test output will be line 11, seems like it shifts by the number of lines the `fakeTemplate` is using.

[HIDDEN]

### Additional contract requirements

- In `.gjs` and `.gts` source, diagnostics for JavaScript tokens after Handlebars content must report locations that match those tokens’ positions in the original source; preceding template or Handlebars content must not shift those locations.
