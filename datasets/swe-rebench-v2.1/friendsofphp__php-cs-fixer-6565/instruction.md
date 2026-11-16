"Use" annotation is converted to simple documentation
Hi !

## Bug report
   - PHP CS Fixer version: 3.2.1
   - Rule: phpdoc_to_comment

"Use" annotation is converted to simple documentation by PHP CS Fixer.

### Code snippet that reproduces the problem


  ```php
  <?php
  class Test {
     /**
     * @use AutoDiscoveredValuesTrait<string>
     */
    use AutoDiscoveredValuesTrait;

  }
  ```

is tranformed into:


  ```php
  <?php
  class Test {
     /*
     * @use AutoDiscoveredValuesTrait<string>
     */
    use AutoDiscoveredValuesTrait;

  }
