nextOpen function: Xdebug has detected a possible infinite loop, and aborted your script with a stack depth of '256' frames
We use the latest spatie/opening-hours version (4.0.1) and the following code will create a possible infinity loop and is aborted with the error message

> Xdebug has detected a possible infinite loop, and aborted your script with a stack depth of '256' frames

:

```
   public function test_infinity_loop()
   {
      $ohConfig = ["monday" => ["00:01-00:00"], "tuesday" => ["00:01-00:00"], "wednesday" => ["00:01-00:00"], "thursday" => ["00:01-00:00"], "friday" => ["00:01-00:00"], "saturday" => ["00:01-00:00"], "sunday" => ["00:01-00:00"]];
      $openingHoursObject = OpeningHours::create($ohConfig);
      $nextOpen = $openingHoursObject->nextOpen(new Carbon("2024-10-22 00:00:00"));
      $this->assertNotNull($nextOpen);
   }
```

And this error also persists if you increase the xdebug.max_nesting_level (e.g. 1024).

I know that the input data should probably be "00:00-23:59" instead of "00:01-00:00" but we get the opening hours from an external data provider and sometimes people create opening hours like this. So it would be great if it was handled by the lib.
