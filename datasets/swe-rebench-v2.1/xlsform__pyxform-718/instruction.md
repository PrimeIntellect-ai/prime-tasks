Trim spaces after :: in language columns
> The survey was to be in multiple languages. So on the columns constraint_message::English (en), and required_message::English (en) I had left a space between the last colon and English as shown :: English (en) . It turns out that XLSForms are sensitive to spaces in some column headers. After I deleted the space, everything was resolved.
-- https://forum.getodk.org/t/dashes-appear-on-the-enketo-webform-help-me-solve-that/41239/2

Seems like we should trim trailing and leading spaces around any text after `::`.
