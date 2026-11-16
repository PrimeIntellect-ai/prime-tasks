Baseline not skipping multiple violations of same reference
Reproducer: https://github.com/gennadigennadigennadi/deptrac/tree/reproducer-skipped-multiple-violations-in-one-file
```yaml
deptrac:
  skip_violations:
    Qossmic\Deptrac\Core\Ast\Parser\Cache\AstFileReferenceFileCache:
      - Qossmic\Deptrac\Supportive\DependencyInjection\Exception\CacheFileException

```
```bash
 Reason                     Ast
 -------------------------- ----------------------------------------------------------------------------------------------------------------------------------------------------------------
  DependsOnDisallowedLayer   Qossmic\Deptrac\Core\Ast\Parser\Cache\AstFileReferenceFileCache must not depend on Qossmic\Deptrac\Supportive\DependencyInjection\Exception\CacheFileException
                             You are depending on token that is a part of a layer that you are not allowed to depend on. (DependencyInjection)
                             /var/www/deptrac/src/Core/Ast/Parser/Cache/AstFileReferenceFileCache.php:139
 -------------------------- ----------------------------------------------------------------------------------------------------------------------------------------------------------------


 -------------------- -----
  Report
 -------------------- -----
  Violations           1
  Skipped violations   1
  Uncovered            24
  Allowed              347
  Warnings             0
  Errors               0
 -------------------- -----


Process finished with exit code 1

```
