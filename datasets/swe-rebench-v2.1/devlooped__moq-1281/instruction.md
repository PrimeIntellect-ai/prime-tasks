`SetupAllProperties` crashes when invoked on a `Mock<T>` subclass
Simply create a `class MyClass : Mock<T>`, create an instance and invoke SetupAllProperties.
