Links with more than 6 pairs of parenthesis aren't parsed correctly
Hi there,

I'm working with URIs that contain [rison](https://github.com/Nanonid/rison) encoded data, which uses parenthesis for serializing json-like objects and arrays.

This can lead to URIs such as [this one](https://godbolt.org/#g:!((g%3A!((g%3A!((g%3A!((h%3AcodeEditor,i%3A(filename%3A'1'%2CfontScale%3A14%2CfontUsePx%3A'0'%2Cj%3A1%2Clang%3Ac%2B%2B%2Cselection%3A(endColumn%3A1%2CendLineNumber%3A1%2CpositionColumn%3A1%2CpositionLineNumber%3A1%2CselectionStartColumn%3A1%2CselectionStartLineNumber%3A1%2CstartColumn%3A1%2CstartLineNumber%3A1)%2Csource%3A'%23include+%3Ciostream%3E%0A%0Aint%20main()%20%7B%0A%20%20%20%20std%3A%3Acout%20%3C%3C%20%22Hello%20World!!%22%20%3C%3C%20std%3A%3Aendl%3B%0A%20%20%20%20return%200%3B%0A%7D%0A')%2Cl%3A'5'%2Cn%3A'1'%2Co%3A'C%2B%2B%20source%20%231'%2Ct%3A'0'))%2Ck%3A50.60347043547407%2Cl%3A'4'%2Cn%3A'0'%2Co%3A''%2Cs%3A0%2Ct%3A'0')%2C(g%3A!((h%3Acompiler%2Ci%3A(compiler%3Aclang1810%2Cfilters%3A(b%3A'0'%2Cbinary%3A'1'%2CbinaryObject%3A'1'%2CcommentOnly%3A'0'%2CdebugCalls%3A'1'%2Cdemangle%3A'0'%2Cdirectives%3A'0'%2Cexecute%3A'0'%2Cintel%3A'0'%2ClibraryCode%3A'0'%2Ctrim%3A'1'%2CverboseDemangling%3A'0')%2CflagsViewOpen%3A'1'%2CfontScale%3A14%2CfontUsePx%3A'0'%2Cj%3A1%2Clang%3Ac%2B%2B%2Clibs%3A!()%2Coptions%3A'-std%3Dc%2B%2B23%20-O3'%2Coverrides%3A!()%2Cselection%3A(endColumn%3A1%2CendLineNumber%3A1%2CpositionColumn%3A1%2CpositionLineNumber%3A1%2CselectionStartColumn%3A1%2CselectionStartLineNumber%3A1%2CstartColumn%3A1%2CstartLineNumber%3A1)%2Csource%3A1)%2Cl%3A'5'%2Cn%3A'0'%2Co%3A'%20x86-64%20clang%2018.1.0%20(Editor%20%231)'%2Ct%3A'0')%2C(h%3Acompiler%2Ci%3A(compiler%3Ag141%2Cfilters%3A(b%3A'0'%2Cbinary%3A'1'%2CbinaryObject%3A'1'%2CcommentOnly%3A'0'%2CdebugCalls%3A'1'%2Cdemangle%3A'0'%2Cdirectives%3A'0'%2Cexecute%3A'0'%2Cintel%3A'0'%2ClibraryCode%3A'0'%2Ctrim%3A'1'%2CverboseDemangling%3A'0')%2CflagsViewOpen%3A'1'%2CfontScale%3A14%2CfontUsePx%3A'0'%2Cj%3A4%2Clang%3Ac%2B%2B%2Clibs%3A!()%2Coptions%3A'-std%3Dc%2B%2B23%20-O3'%2Coverrides%3A!()%2Cselection%3A(endColumn%3A1%2CendLineNumber%3A1%2CpositionColumn%3A1%2CpositionLineNumber%3A1%2CselectionStartColumn%3A1%2CselectionStartLineNumber%3A1%2CstartColumn%3A1%2CstartLineNumber%3A1)%2Csource%3A1)%2Cl%3A'5'%2Cn%3A'0'%2Co%3A'%20x86-64%20gcc%2014.1%20(Editor%20%231)'%2Ct%3A'0')%2C(h%3Acompiler%2Ci%3A(compiler%3Ag141%2Cfilters%3A(b%3A'0'%2Cbinary%3A'1'%2CbinaryObject%3A'1'%2CcommentOnly%3A'0'%2CdebugCalls%3A'1'%2Cdemangle%3A'0'%2Cdirectives%3A'0'%2Cexecute%3A'1'%2Cintel%3A'0'%2ClibraryCode%3A'0'%2Ctrim%3A'1'%2CverboseDemangling%3A'0')%2CflagsViewOpen%3A'1'%2CfontScale%3A14%2CfontUsePx%3A'0'%2Cj%3A2%2Clang%3Ac%2B%2B%2Clibs%3A!()%2Coptions%3A'-std%3Dc%2B%2B23%20-E'%2Coverrides%3A!()%2Cselection%3A(endColumn%3A1%2CendLineNumber%3A1%2CpositionColumn%3A1%2CpositionLineNumber%3A1%2CselectionStartColumn%3A1%2CselectionStartLineNumber%3A1%2CstartColumn%3A1%2CstartLineNumber%3A1)%2Csource%3A1)%2Cl%3A'5'%2Cn%3A'0'%2Co%3A'%20x86-64%20gcc%2014.1%20(Editor%20%231)'%2Ct%3A'0')%2C(h%3Acompiler%2Ci%3A(compiler%3Aclang1701%2Cfilters%3A(b%3A'0'%2Cbinary%3A'1'%2CbinaryObject%3A'1'%2CcommentOnly%3A'0'%2CdebugCalls%3A'1'%2Cdemangle%3A'0'%2Cdirectives%3A'0'%2Cexecute%3A'1'%2Cintel%3A'0'%2ClibraryCode%3A'0'%2Ctrim%3A'1'%2CverboseDemangling%3A'0')%2CflagsViewOpen%3A'1'%2CfontScale%3A14%2CfontUsePx%3A'0'%2Cj%3A3%2Clang%3Ac%2B%2B%2Clibs%3A!()%2Coptions%3A'-std%3Dc%2B%2B23%20-E'%2Coverrides%3A!()%2Cselection%3A(endColumn%3A1%2CendLineNumber%3A1%2CpositionColumn%3A1%2CpositionLineNumber%3A1%2CselectionStartColumn%3A1%2CselectionStartLineNumber%3A1%2CstartColumn%3A1%2CstartLineNumber%3A1)%2Csource%3A1)%2Cl%3A'5'%2Cn%3A'0'%2Co%3A'%20x86-64%20clang%2017.0.1%20(Editor%20%231)'%2Ct%3A'0'))%2Ck%3A49.396529564525935%2Cl%3A'4'%2Cm%3A100%2Cn%3A'0'%2Co%3A''%2Cs%3A0%2Ct%3A'0'))%2Cl%3A'2'%2Cm%3A69.39799331103679%2Cn%3A'0'%2Co%3A''%2Ct%3A'0')%2C(g%3A!((h%3Aoutput%2Ci%3A(compilerName%3A'x86-64%20gcc%2012.1'%2Ceditorid%3A1%2CfontScale%3A14%2CfontUsePx%3A'0'%2Cj%3A1%2Cwrap%3A'1')%2Cl%3A'5'%2Cn%3A'0'%2Co%3A'Output%20of%20x86-64%20clang%2018.1.0%20(Compiler%20%231)'%2Ct%3A'0')%2C(h%3Aoutput%2Ci%3A(compilerName%3A'x86-64%20gcc%2013.2'%2Ceditorid%3A1%2CfontScale%3A14%2CfontUsePx%3A'0'%2Cj%3A4%2Cwrap%3A'1')%2Cl%3A'5'%2Cn%3A'0'%2Co%3A'Output%20of%20x86-64%20gcc%2014.1%20(Compiler%20%234)'%2Ct%3A'0'))%2Cheader%3A()%2Cl%3A'4'%2Cm%3A30.60200668896321%2Cn%3A'0'%2Co%3A''%2Cs%3A0%2Ct%3A'0'))%2Cl%3A'3'%2Cn%3A'0'%2Co%3A''%2Ct%3A'0'))%2Cversion%3A4).

While it looks kind of odd, it's still a valid URI as far I can tell.
However, when I tried putting this into a mdbook, it simply rendered the markdown line as text.

Example input:
```markdown
[1](https://rust.org/something%3A())
[2](https://rust.org/something%3A(()))
[3](https://rust.org/something%3A((())))
[4](https://rust.org/something%3A(((()))))
[5](https://rust.org/something%3A((((())))))
[6](https://rust.org/something%3A(((((()))))))
[7](https://rust.org/something%3A((((((())))))))
[8](https://rust.org/something%3A(((((((()))))))))
[9](https://rust.org/something%3A((((((((())))))))))
[10](https://rust.org/something%3A(((((((((()))))))))))
[11](https://rust.org/something%3A((((((((((())))))))))))
[12](https://rust.org/something%3A(((((((((((()))))))))))))
[13](https://rust.org/something%3A((((((((((((())))))))))))))
[14](https://rust.org/something%3A(((((((((((((()))))))))))))))
```
`pulldown_cmark::html::push_html`'s output:
```html
<p><a href="https://rust.org/something%3A()">1</a><br />
<a href="https://rust.org/something%3A(())">2</a><br />
<a href="https://rust.org/something%3A((()))">3</a><br />
<a href="https://rust.org/something%3A(((())))">4</a><br />
<a href="https://rust.org/something%3A((((()))))">5</a><br />
<a href="https://rust.org/something%3A(((((())))))">6</a><br />
[7](https://rust.org/something%3A((((((())))))))<br />
[8](https://rust.org/something%3A(((((((()))))))))<br />
[9](https://rust.org/something%3A((((((((())))))))))<br />
[10](https://rust.org/something%3A(((((((((()))))))))))<br />
[11](https://rust.org/something%3A((((((((((())))))))))))<br />
[12](https://rust.org/something%3A(((((((((((()))))))))))))<br />
[13](https://rust.org/something%3A((((((((((((())))))))))))))<br />
[14](https://rust.org/something%3A(((((((((((((()))))))))))))))</p>
```

### Additional contract requirements

- Specifically, parse a link destination containing 30 nested parenthesis pairs, but leave a link with 40 nested pairs as literal Markdown text, including its `[40]` link syntax.
