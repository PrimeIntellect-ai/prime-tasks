"Cannot read properties of undefined" when xml contain <script ...>
Hi, I test with 2 different version to determine if the problem is my XML or prettier. So the problem seems to be the last version of prettier.

Version works :
- plugin-xml v2.2.0
- prettier 2.8.8

Version not works :
- plugin-xml v3.2.0
- prettier 3.0.3

File to format :
`./module/templates.xml`
or
`/home/project/module/templates.xml`

Command :
`./../node_modules/.bin/prettier --plugin @prettier/plugin-xml --xml-whitespace-sensitivity "ignore" --prose-wrap always --tab-width 4 --no-bracket-spacing --print-width 120 --write ./module/`

Expected result :
`module/templates.xml 6ms`

Error result :
```
module/templates.xml
[error] email_cc/views/web_assets.xml: TypeError: Cannot read properties of undefined (reading '0')
[error]     at embed (file:///home/project/node_modules/@prettier/plugin-xml/src/embed.js:129:40)
[error]     at recurse (file:///usr/lib/node_modules/prettier/index.mjs:17708:20)
[error]     at AstPath.each (file:///usr/lib/node_modules/prettier/index.mjs:17009:9)
[error]     at recurse (file:///usr/lib/node_modules/prettier/index.mjs:17703:15)
[error]     at AstPath.call (file:///usr/lib/node_modules/prettier/index.mjs:16971:14)
[error]     at recurse (file:///usr/lib/node_modules/prettier/index.mjs:17705:15)
[error]     at AstPath.each (file:///usr/lib/node_modules/prettier/index.mjs:17009:9)
[error]     at recurse (file:///usr/lib/node_modules/prettier/index.mjs:17703:15)
[error]     at AstPath.call (file:///usr/lib/node_modules/prettier/index.mjs:16971:14)
[error]     at recurse (file:///usr/lib/node_modules/prettier/index.mjs:17705:15)
```

Content of file `module/templates.xml` :
```
<odoo>
    <template id="assets_backend" name="assets" inherit_id="web.assets_backend">
        <xpath expr="." position="inside">
            <script type="text/javascript" src="/module/static/src/js/message.js" />
        </xpath>
    </template>
</odoo>
```

Thanks for your support, I can work with version 2 ;-)
