Fails to calculate INDEX() function
Sample formula:
=INDEX({"First","Second","Third","Fourth","Fifth","Sixth","Seventh"}, 4)

Errors thrown:
Undefined offset: 3 in `/var/www/html/hoosh/excel_v2/vendor/phpoffice/phpspreadsheet/src/PhpSpreadsheet/Calculation/LookupRef.php on line 603`
`Undefined index: in /var/www/html/hoosh/excel_v2/vendor/phpoffice/phpspreadsheet/src/PhpSpreadsheet/Calculation/LookupRef.php on line 610`

### Additional contract requirements

- For the tested INDEX case with a two-column matrix and the column number omitted, the calculated result must be `abc`.
