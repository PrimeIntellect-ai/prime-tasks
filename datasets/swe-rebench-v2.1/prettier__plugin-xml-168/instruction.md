TypeError: Cannot read property 'startLine' of undefined (v0.13.0)
I get the following error if i try to update to newest version

```

$ prettier "{**/*,*}.*" -u --list-different
--
1183 | [error] dir\file.xml: TypeError: Cannot read property 'startLine' of undefined
1184 | [error]     at Object.element (C:\drone\src\node_modules\@prettier\plugin-xml\src\printer.js:336:34)
1185 | [error]     at Object.genericPrint [as print] (C:\drone\src\node_modules\@prettier\plugin-xml\src\printer.js:412:30)
1186 | [error]     at callPluginPrintFunction (C:\drone\src\node_modules\prettier\index.js:14718:18)
1187 | [error]     at C:\drone\src\node_modules\prettier\index.js:14649:47
1188 | [error]     at Object.printComments (C:\drone\src\node_modules\prettier\index.js:14305:19)
1189 | [error]     at printGenerically (C:\drone\src\node_modules\prettier\index.js:14649:22)
1190 | [error]     at FastPath.call (C:\drone\src\node_modules\prettier\index.js:14441:20)
1191 | [error]     at C:\drone\src\node_modules\@prettier\plugin-xml\src\printer.js:308:27
1192 | [error]     at Array.map (<anonymous>)
1193 | [error]     at Object.element (C:\drone\src\node_modules\@prettier\plugin-xml\src\printer.js:304:19)


```

*dir\file.xml*
```yml
<?xml version="1.0" encoding="utf-8" standalone="yes" ?>
<Event>
    <Process id="XXX.Notification">

    </Process>
    <!--<Process id="XXX.Notification.Tmpl" >
        <Condition>[v:NType] == 'Tmpl'</Condition>
    </Process>-->
</Event>

```

### Additional contract requirements

- Formatting the reported XML input must complete without throwing.
- For an input containing `<style> </style>`, default formatting must emit `<style> </style>`, and formatting with `xmlWhitespaceSensitivity: "ignore"` must emit `<style />`.
