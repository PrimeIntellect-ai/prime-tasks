Bad state: typedef ... (TypeAliasElementImpl) cannot have parameter
### steps to reproduce

1. run `dart create -t package dartdoc_issue`
2. add the code below in `lib/dartdoc_issue.dart`
```dart
/// a typedef for a "multi-argument" [Function]
typedef Foo<T, S, U> = T Function(S, U);

/// a typedef for an async "multi-argument" [Function]
typedef Bar<T, S, U> = Foo<Future<T>, S, U>;
```
3. run `dart doc .`

### expected results

no errors

### actual results

<details>
  <summary>logs</summary>

  ```console
  ➜  dartdoc_issue dart doc .
Documenting dartdoc_issue...
Initialized dartdoc with 40 libraries
Generating docs for library dartdoc_issue from package:dartdoc_issue/dartdoc_issue.dart...
  warning: dartdoc_issue has no library level documentation comments
    from dartdoc_issue: (file:///Volumes/ROG/dev/dartdoc_issue/lib/dartdoc_issue.dart:1:9)

dartdoc 5.1.0-dev (/Volumes/ROG/dev/dartdoc_issue/dartdev) failed: Bad state: typedef Bar<out T, in S, in U> = Future<T> Function(S, U) (TypeAliasElementImpl) cannot have parameters
#0      ModelElement.parameters.<anonymous closure> (package:dartdoc/src/model/model_element.dart:882:7)
#1      ModelElement.parameters (package:dartdoc/src/model/model_element.dart:912:4)
#2      ModelElement.parameters (package:dartdoc/src/model/model_element.dart)
#3      FunctionTypedef.referenceChildren (package:dartdoc/src/model/typedef.dart:141:31)
#4      CommentReferable.referenceBy (package:dartdoc/src/model/comment_referable.dart:115:38)
#5      _getMatchingLinkElementCommentReferable (package:dartdoc/src/markdown_processor.dart:225:31)
#6      getMatchingLinkElement (package:dartdoc/src/markdown_processor.dart:266:16)
#7      _makeLinkNode (package:dartdoc/src/markdown_processor.dart:233:16)
#8      new MarkdownDocument.withElementLinkResolver.linkResolver (package:dartdoc/src/markdown_processor.dart:340:14)
#9      LinkSyntax._resolveReferenceLink (package:markdown/src/inline_parser.dart:1057:34)
#10     LinkSyntax._tryCreateReferenceLink (package:markdown/src/inline_parser.dart:1085:12)
#11     LinkSyntax.close (package:markdown/src/inline_parser.dart:982:14)
#12     InlineParser._linkOrImage (package:markdown/src/inline_parser.dart:152:29)
#13     InlineParser.parse (package:markdown/src/inline_parser.dart:108:9)
#14     MarkdownDocument._parseInlineContent (package:dartdoc/src/markdown_processor.dart:383:67)
#15     MarkdownDocument._parseInlineContent (package:dartdoc/src/markdown_processor.dart:388:9)
#16     MarkdownDocument.parseMarkdownText (package:dartdoc/src/markdown_processor.dart:373:5)
#17     Documentation._parseDocumentation (package:dartdoc/src/model/documentation.dart:61:21)
#18     Documentation._renderDocumentation (package:dartdoc/src/model/documentation.dart:40:23)
#19     Documentation.asOneLiner (package:dartdoc/src/model/documentation.dart:32:7)
#20     ModelElement.oneLineDoc (package:dartdoc/src/model/model_element.dart:831:50)
#21     __deduplicated_lib_templates_html__typedef_html_partial_type_2 (package:dartdoc/src/generator/templates.aot_renderers_for_html.dart:3579:25)
#22     _deduplicated_lib_templates_html__typedef_html (package:dartdoc/src/generator/templates.aot_renderers_for_html.dart:3505:18)
#23     _renderLibrary_partial_typedef_10 (package:dartdoc/src/generator/templates.aot_renderers_for_html.dart:2676:5)
#24     renderLibrary (package:dartdoc/src/generator/templates.aot_renderers_for_html.dart:1153:20)
#25     HtmlAotTemplates.renderLibrary (package:dartdoc/src/generator/templates.dart:157:30)
#26     DartdocGeneratorBackend.generateLibrary (package:dartdoc/src/generator/dartdoc_generator_backend.dart:192:29)
#27     GeneratorFrontEnd._generateDocs (package:dartdoc/src/generator/generator_frontend.dart:72:27)
#28     GeneratorFrontEnd.generate (package:dartdoc/src/generator/generator_frontend.dart:23:11)
#29     Dartdoc.generateDocsBase (package:dartdoc/src/dartdoc.dart:181:21)
<asynchronous suspension>
#30     Dartdoc.generateDocs (package:dartdoc/src/dartdoc.dart:223:24)
<asynchronous suspension>
#31     Dartdoc.executeGuarded.<anonymous closure> (package:dartdoc/src/dartdoc.dart:261:9)
<asynchronous suspension>
  ```

</details>

`Dart SDK version: 2.17.6 (stable) (Tue Jul 12 12:54:37 2022 +0200) on "macos_arm64"`
