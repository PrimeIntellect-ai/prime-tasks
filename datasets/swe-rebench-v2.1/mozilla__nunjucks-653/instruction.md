Macro recursion issue: Variables in macros are not stored on the stack
Consider the following template that renders a list of fully qualified property names from a JSON schema:

    {% macro typeTable(node, prefix = "", name = "" %}
      {% set nodeName = prefix + ("." if prefix) + name) %}
      {% if nodeName %}
        <tr>
          <td><code>{{ nodeName | safe }}</code></td>
          <td>{{ node.type }}</td>
          <td>
            {% markdown %}{{ node.description }}{% endmarkdown %}
          </td>
        </tr>
      {% endif %}
      {% if node.type == "object" %}
        {% for propName, propSpec in node.properties %}
          {{ typeTable(propSpec, nodeName, propName) }}
        {% endfor %}
      {% endif %}
    {% endmacro %}

    <body>
      <table class='table table-bordered'>
        <thead>
          <tr>
            <th>Qualified name</th>
            <th>Type</th>
            <th>Description</th>
          </tr>
        </thead>
        <tbody>
          {{ typeTable(schema) }}
        </tbody>
      </table>
    </body>


Where `schema` is for example the following JSON schema

    {
      "$schema": "http://json-schema.org/draft-04/schema",
      "type": "object",
      "properties": {
        "id": {
          "type": "string",
          "description": "The ID of the node"
        },
        "name": {
          "type": "string",
          "description": "The name of the node"
        },
        "status": {
          "type": "object",
          "description": "The status of the node",
          "properties": {
            "vm": {
              "type": "string"
            },
            "app": {
              "type": "string"
            }
          }
        },
        "url": {
          "type": "string",
          "format": "uri",
          "description": "The URL of the node"
        }
      }
    }

The expected result is a table with the following "qualified names":

    id
    name
    status
    status.vm
    status.app
    url

However the variable `nodeName` seems to scoped per declaration (i.e. there is only one instance) and not scoped per invocation. This means that changes to `nodeName` in recursive calls of `typeTable` can be seen by the caller. This results in the following "qualified names":

    id
    id.name
    id.name.status
    id.name.status.vm
    id.name.status.vm.app
    id.name.status.vm.app.url
