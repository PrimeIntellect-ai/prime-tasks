Parsing does not work on server side
Because of the changes made by [this commit](https://github.com/remarkablemark/html-react-parser/commit/1fb5ee2), parsing does not work on the server side. This is a problem for server-rendered React applications.

### Additional contract requirements

- Parsing must not skip `<script>` elements. A `<script>` element must be parsed into a React element whose `type` is `'script'`, and its raw text content must be preserved without HTML-escaping.
- The raw text content of a `<script>` element is exposed on the parsed React element as `props.dangerouslySetInnerHTML.__html` (the same output shape used for `<style>` content). Rendering the parsed element must reproduce the original `<script>...</script>` markup.
