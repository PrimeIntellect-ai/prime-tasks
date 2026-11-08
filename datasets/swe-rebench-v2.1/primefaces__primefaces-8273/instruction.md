primefaces.MOVE_SCRIPTS_TO_BOTTOM: Import with additional parameters
**Description**
The function primefaces.MOVE_SCRIPTS_TO_BOTTOM, doesn't move addtional parameters of an script import to the bottom.
It works well when a <script> tag has only src / type attributes, but everything else will be deleted during the move process.

For example:

XHTML:
<script src="https://primefaces.org/primefaces.js"
type="text/javascript" charset="UTF-8"
data-domain-script="OneParameterValue" />

With primefaces.MOVE_SCRIPTS_TO_BOTTOM=off the output in the browser is:
<script src="https://primefaces.org/primefaces.js"
type="text/javascript" charset="UTF-8" data-domain-script="OneParameterValue"></script>

With primefaces.MOVE_SCRIPTS_TO_BOTTOM=on:
<script type="text/javascript" src="https://primefaces.org/primefaces.js">

**Describe the solution you would like**
There are two possible solutions:
1. Skip imports with additional parameters
2. Change the move process, that addtional parameters are considered.
