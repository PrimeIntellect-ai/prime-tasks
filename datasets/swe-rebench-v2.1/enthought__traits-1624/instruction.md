Clone traits does not seem to work with dynamic Enum
Noticed that issue on Linux with traits 6.3.2

When my class has a trait which value are set by a dynamic Enum, it is not correctly copied by ``clone_traits``. Here is a small example to reproduce the issue, (it might not be the best example, but I did not want to spend too much time building a fake example). We can talk about the real case where I noticed the issue.

```
from traits.api import Enum, HasStrictTraits, List, Str, Tuple


class Company(HasStrictTraits):
    #: List of departments
    departments = List(Str)

    #: Projects: (name, department)
    projects = List(Tuple(Str, Enum(values="departments")))

    def set_departments(self):
       # This is not realistic, it just to demontrate the issue
       self.departments = ["marketing", "training", "consulting"]


def demo():
    company = Company()
    company.set_departments()
    projects = []
    for i, project in enumerate(["hello", "world", "bye"]):
        projects.append((project, company.departments[i]))
    company.projects = projects

    cie = company.clone_traits()
    print(company.projects)
    print(cie.projects)  # This is always empty


if __name__ == "__main__":
    demo()
```
