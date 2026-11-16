`parse_options_header` rejects q values "0" and "1"
provide an accept header such as `en;q=0` or `en;q=1` ->

q values 0 or 1 are dropped.  The [RFC 9110](https://www.rfc-editor.org/rfc/rfc9110#name-quality-values) indicates that the decimal is optional however we are rejecting q values that do not contain a decimal

Environment:

- Python version: 3.11.4
- Werkzeug version: 2.3.6
