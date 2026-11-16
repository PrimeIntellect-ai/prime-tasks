Cannot read property 'name' of undefined at getPropName
env:
"eslint": "^5.0.0",
"eslint-plugin-react": "^7.10.0",


I got a error when use eslint --ext .js src;
the error is happened in `eslint-plugin-react\lib\rules\jsx-props-no-multi-spaces.js getPropName `  function, this function like can't handle the Node type, and I console the Node type, there is

<code>
{
  type: 'JSXMemberExpression',
  start: 1243,
  end: 1252,
  loc:
   SourceLocation {
     start: Position { line: 43, column: 9 },
     end: Position { line: 43, column: 18 } },
  range: [ 1243, 1252 ],
  object:
   Node {
     type: 'JSXIdentifier',
     start: 1243,
     end: 1247,
     loc: SourceLocation { start: [Object], end: [Object] },
     range: [ 1243, 1247 ],
     name: 'Menu',
     _babelType: 'JSXIdentifier',
     parent: [Circular] },
  property:
   Node {
     type: 'JSXIdentifier',
     start: 1248,
     end: 1252,
     loc: SourceLocation { start: [Object], end: [Object] },
     range: [ 1248, 1252 ],
     name: 'Item',
     _babelType: 'JSXIdentifier',
     parent: [Circular] },
  _babelType: 'JSXMemberExpression',
  parent:
   Node {
     type: 'JSXOpeningElement',
     start: 1242,
     end: 1269,
     loc: SourceLocation { start: [Object], end: [Object] },
     range: [ 1242, 1269 ],
     attributes: [ [Object] ],
     name: [Circular],
     selfClosing: false,
     _babelType: 'JSXOpeningElement',
     parent:
      Node {
        type: 'JSXElement',
        start: 1242,
        end: 1325,
        loc: [Object],
        range: [Array],
        openingElement: [Circular],
        closingElement: [Object],
        children: [Array],
        _babelType: 'JSXElement',
        parent: [Object] } } }
</code>
