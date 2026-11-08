Creating page without default constructor
Hi,

I've got class extending FluentWebPage that has constructor with 2 parameters and I want to initcialize it.
It seems that there is no way to do it in FluentLenium.
There is only createPage(TestPage.class) method;
Is there any way to create page out of object instance? Like in Webdriver
ComplexPageObject page = new ComplexPageObject("expected title", driver);
PageFactory.initElements(driver, page);

### Additional contract requirements

- A Fluent page that requires a two-argument constructor must be creatable and initialized without a no-argument constructor. `createPage(Class<T> classOfPage, Object... params)` constructs the page using the supplied arguments, preserves values set by its constructor, and initializes its Fluent infrastructure, including its driver and base URL.
