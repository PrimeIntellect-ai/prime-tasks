Export to csv from excel including hyperlink
Hi PHPOffice,

I am looking for a way to export my XLSX file to CSV where some columns have a hyperlink and I could not figure out how to export the file with a hyperlink instead of the text on which hyperlink is applied.

here is my code to export to CSV:

```
require constant('EO_ECIE_DIR').'vendor/autoload.php';
 $xl_reader = new Xlsx();
 $sheets = $xl_reader->load(self::$_file);

 $sheet_names = $sheets->getSheetNames();

 $csv_writer = new Csv($sheets);
 if(is_array($sheet_names) and !empty($sheet_names[0])){

	$csv_writer->setSheetIndex(0);
       $csv_writer->save(self::$_file.'.csv');
       self::$_file = self::$_file.'.csv';
}

```
Help is appreciated as I have already googled a lot before writing a query here.

Thanks in advance.

### Additional contract requirements

- The CSV writer (`PhpOffice\PhpSpreadsheet\Writer\Csv`) must offer a boolean option set with `setPreferHyperlinkToLabel(bool $preferHyperlinkToLabel)`. It is off by default, so CSV output is unchanged unless it is turned on.
- When the option is on, a cell that has a hyperlink is written as the hyperlink's URL instead of its displayed text. Cells without a hyperlink are written as usual.
