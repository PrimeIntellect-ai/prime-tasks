Issue with `Memory` simulation
Hi,

we are currently updating Amaranth version in Coreblocks (https://github.com/kuznia-rdzeni/coreblocks/pull/461) and unexpectedly some unit tests started to fail. Part of failing unit tests check the whole core on assembler programs. Similar tests using Cocotb and Verilator passed successfully, so I assume some problems with simulation inside Amaranth (as unit tests use amaranth tests framework). After some investigation it looks like the issue is related #893. Here is a reproduction example:

```py
class MemoryReproduce(TestCaseWithSimulator):
    class DUT(Elaboratable):
        def __init__(self):
            pass

        def elaborate(self, platform):
            m = Module()
            self.mem = Memory(width=8, depth=8)
            m.submodules.read_port = self.read_port = self.mem.read_port()
            m.submodules.write_port = self.write_port = self.mem.write_port()
            return m

    def test_minimal(self):
        m = self.DUT()

        def process():
            yield m.read_port.addr.eq(1)
            yield m.read_port.en.eq(1)
            yield
            print((yield m.read_port.data))
            yield
            yield m.write_port.addr.eq(2)
            yield m.write_port.data.eq(14)
            yield m.write_port.en.eq(1)
            print((yield m.read_port.data))
            yield
            yield m.write_port.en.eq(0)
            print((yield m.read_port.data))
            yield
            print((yield m.read_port.data))
            yield
            print((yield m.read_port.data))

        with self.run_simulation(m) as sim:
            sim.add_sync_process(process)
```

Output for this test case:
```
0
0
0
14
0
```

![obraz](https://github.com/amaranth-lang/amaranth/assets/34948061/6ec43920-0bf3-4cec-a369-fac6a60c6450)


Idea is that we try to read memory from the one address and write to the other one. So we expect that writing has no impact on reading. But as you can see that is not a case in Amaranth simulation. Write cause that on read data output port there is visible written value for one cycle.
