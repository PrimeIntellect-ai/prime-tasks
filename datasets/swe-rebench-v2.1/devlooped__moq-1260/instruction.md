Setup property doesn't work as expected
Hi everyone, from time to time we are performing a regular nuget update, and currently part of our previously working tests are not working any more.

IDE: VS 2022
Test Runner: vstest
Test framework: mstest
.NET Version: 4.8

Steps to reproduce:
```
using Microsoft.VisualStudio.TestTools.UnitTesting;
using Moq;

namespace MoqIssueTestProject
{
    public interface ITest1Interface
    {
        bool IsDone { get; set; }
    }

    public interface ITest2Interface : ITest1Interface
    {
    }

    public abstract class AbstractClass
    {
        public virtual bool IsDone { get; set; }
    }

    public class InheritedClass : AbstractClass, ITest1Interface
    {
    }

    public class ClassToTest
    {
        private readonly ITest1Interface instance;

        public ClassToTest(ITest1Interface instance)
        {
            this.instance = instance;
        }

        public void DoSomething()
        {
            instance.IsDone = true;
        }
    }

    [TestClass]
    public class UnitTest1
    {
        [TestMethod]
        public void TestMethod1()
        {
            // Arrange
            var mockDependency = new Mock<InheritedClass>();
            var mockDependency2 = mockDependency.As<ITest2Interface>().SetupProperty(x => x.IsDone, false);
            var tc = new ClassToTest(mockDependency2.Object);

            // Act
            tc.DoSomething();

            // Verify
            mockDependency.VerifySet(x => x.IsDone = true, Times.Once()); // Fine
            mockDependency2.VerifySet(x => x.IsDone = true, Times.Once()); // Fine
            Assert.IsTrue(mockDependency2.Object.IsDone); // This fails
            Assert.IsTrue(mockDependency.Object.IsDone); // This fails
        }
    }
}
```

Last version where it was working as expected: 4.16.1
