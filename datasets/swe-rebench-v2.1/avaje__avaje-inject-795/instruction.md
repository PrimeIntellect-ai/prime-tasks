Duplicate class names
There are two classes with the same name in different packages, causing the dependency injection module to malfunction.

```
/Users/yein/work/mahu/mahu-admin/mahu-admin-web/build/generated/sources/annotationProcessor/java/main/cool/houge/mahu/admin/MahuAdminModule.java:26: error: The single-type-import of DictController$DI has already defined a type with the same simple name
import cool.houge.mahu.admin.controller.system.DictController$DI;
^
/Users/yein/work/mahu/mahu-admin/mahu-admin-web/build/generated/sources/annotationProcessor/java/main/cool/houge/mahu/admin/MahuAdminModule.java:216: error: Reference to DictController$DI is ambiguous
    DictController$DI.build(builder);
    ^
  Both class cool.houge.mahu.admin.controller.DictController$DI from cool.houge.mahu.admin.controller and class cool.houge.mahu.admin.controller.system.DictController$DI from cool.houge.mahu.admin.controller.system match
/Users/yein/work/mahu/mahu-admin/mahu-admin-web/build/generated/sources/annotationProcessor/java/main/cool/houge/mahu/admin/MahuAdminModule.java:452: error: Reference to DictController$DI is ambiguous
    DictController$DI.build(builder);
```

This is a Java compilation error caused by having two inner classes named DictController$DI in different packages:
1. cool.houge.mahu.admin.controller.DictController$DI
2. cool.houge.mahu.admin.controller.system.DictController$DI
