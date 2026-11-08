Empty CSS custom values generate an error
Hello I'm also running with an issue similar to the one describe here

https://github.com/twbs/bootstrap/issues/38061

when including part of the boostrap css in an epub V3 file as epubcheck is reporting an error on empty value for custom css properties. After verification I agree with the boostrap team that it is legal CSS for custom properties to be empty whereas it is not legal for regular properties to be empty and it seems it is a bug in epubcheck to report this as an error.

To replicate the error simply take the boostrap CSS here

https://cdn.jsdelivr.net/npm/bootstrap@5.2.3/dist/css/bootstrap.css

and include it in an epub3 file, then run epubcheck vs 5.0.1 and you will get an error like this:

ERROR(CSS-008): ../untitled.epub/OEBPS/Styles/main.css(2731,25): An error occurred while parsing the CSS: Token ";" not allowed here, expecting a property value.
