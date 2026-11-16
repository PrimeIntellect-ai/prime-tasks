Strip whitespaces at the end of closing markups.
Spaces after the end of the markup name in a closing tag are valid XML (See: https://www.w3.org/TR/REC-xml/#sec-starttags ). Yet the pares considers them part of the markup name and so checking for matching start and close may fail.
