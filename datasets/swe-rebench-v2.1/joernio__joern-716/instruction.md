Uniform initialization not detected in C++
The lines for ```int brace{10};``` and ```int uniform[]{0,1,2};``` are equivalent to ```int brace=10``` and ```int uniform[]={0,1,2};```, respectively, but are interpreted by Joern as Block nodes.
```
#include <iostream>

using namespace std;

int main() {

  int brace{10};

  cout<<brace<<endl;

  int uniform[]{0,1,2};

  for (int i : uniform) {
      cout<<i<<endl;
  }

  return 0;
}
```
