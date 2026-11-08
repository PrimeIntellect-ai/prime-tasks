display-name rule quotes handling
If JSON style is used for defining components, rule is not handle "displayName" option.
The following patterns are considered warnings:
`var Hello = React.createClass({
  "displayName": "Hello",
  "render": function() {
    return <div>Hello {this.props.name}</div>;
  }
});`
but its valid code i think.
