"omit_project_prefix = true" is ignored in interface definitions, but not when the interface is instantiated in a module.
Module instantiation:

**Veryl:**
```
module axi_test () {

    inst v: axi4_if::<32, 4, 1, 8, 8, 8, 8, 8>;

    inst u: axi3_if::<32, 4, 1>;
}

pub interface axi4_if::<ADDR_W: const, DATA_W_BYTES: const, ID_W: const, AWUSER_W: const, WUSER_W: const, BUSER_W: const, ARUSER_W: const, RUSER_W: const> {

    const AXI_VERSION     : u32 = 4;
    const ADDRESS_WIDTH   : u32 = ADDR_W;
    const DATA_WIDTH_BYTES: u32 = DATA_W_BYTES;
    const NUM_BURSTS_LEN  : u32 = 8;
    const LOCK_LEN        : u32 = 1;
    const ID_LENGTH       : u32 = ID_W;
    const AWUSER_LENGTH   : u32 = AWUSER_W;
    const WUSER_LENGTH    : u32 = WUSER_W;
    const BUSER_LENGTH    : u32 = BUSER_W;
    const ARUSER_LENGTH   : u32 = ARUSER_W;
    const RUSER_LENGTH    : u32 = RUSER_W;

    type addr_t       = logic<ADDRESS_WIDTH>         ;
    type data_t       = logic<(DATA_WIDTH_BYTES * 8)>;
    type strb_t       = logic<DATA_WIDTH_BYTES>      ;
    type num_bursts_t = logic<NUM_BURSTS_LEN>        ;
    type lock_t       = logic<LOCK_LEN>              ;
    type id_t         = logic<ID_LENGTH>             ;
    type awuser_t     = logic<AWUSER_LENGTH>         ;
    type wuser_t      = logic<WUSER_LENGTH>          ;
    type buser_t      = logic<BUSER_LENGTH>          ;
    type aruser_t     = logic<ARUSER_LENGTH>         ;
    type ruser_t      = logic<RUSER_LENGTH>          ;

    ///Bus clock and reset
    var ACLK   : clock_posedge ;
    var ARESETN: reset_sync_low;

    ///Write address channel
    var AWVALID : logic          ;
    var AWREADY : logic          ;
    var AWADDR  : addr_t         ;

   (...)

}
```

**Generated SystemVerilog code:**

```
module axi_test ();

    __axi4_if__32__4__1__8__8__8__8__8 v ();

endmodule

interface test_axi___axi4_if__32__4__1__8__8__8__8__8;

    localparam int unsigned AXI_VERSION      = 4;
    localparam int unsigned ADDRESS_WIDTH    = 32;
    localparam int unsigned DATA_WIDTH_BYTES = 4;
    localparam int unsigned NUM_BURSTS_LEN   = 8;
    localparam int unsigned LOCK_LEN         = 1;
    localparam int unsigned ID_LENGTH        = 1;
    localparam int unsigned AWUSER_LENGTH    = 8;
    localparam int unsigned WUSER_LENGTH     = 8;
    localparam int unsigned BUSER_LENGTH     = 8;
    localparam int unsigned ARUSER_LENGTH    = 8;
    localparam int unsigned RUSER_LENGTH     = 8;

    typedef logic [ADDRESS_WIDTH-1:0]          addr_t      ;
    typedef logic [(DATA_WIDTH_BYTES * 8)-1:0] data_t      ;
    typedef logic [DATA_WIDTH_BYTES-1:0]       strb_t      ;
    typedef logic [NUM_BURSTS_LEN-1:0]         num_bursts_t;
    typedef logic [LOCK_LEN-1:0]               lock_t      ;
    typedef logic [ID_LENGTH-1:0]              id_t        ;
    typedef logic [AWUSER_LENGTH-1:0]          awuser_t    ;
    typedef logic [WUSER_LENGTH-1:0]           wuser_t     ;
    typedef logic [BUSER_LENGTH-1:0]           buser_t     ;
    typedef logic [ARUSER_LENGTH-1:0]          aruser_t    ;
    typedef logic [RUSER_LENGTH-1:0]           ruser_t     ;

    ///Bus clock and reset
    logic ACLK   ;
    logic ARESETN;

    ///Write address channel
    logic                AWVALID ;
    logic                AWREADY ;
    addr_t               AWADDR  ;

    (...)

endinterface
```




[Test case](https://github.com/janschiefer/test_axi)
