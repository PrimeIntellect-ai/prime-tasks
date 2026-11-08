panic: interface conversion error when map have only number in string key
Sample code to reproduce

```package main

import (
	"bytes"
	"fmt"
	"strings"

	"github.com/diegoholiveira/jsonlogic"
)

func main() {

	logic := strings.NewReader(`{"and":[{">":[{"*":[{"/":[{"var":"tradeItems.43443.quantity.REJECTED"},{"var":"tradeItems.43443.quantity.RECEIVED"}]},100]},0.1]}]}`)
	data := strings.NewReader(`{"tradeItems":{"43443":{"lineItemNo":1,"itemName":"Item16","SKUCode":"43443","HSNCode":"45455","quantity":{"ACCEPTED":4500,"APPROVED":0,"DESTRUCTED":0,"INTRANSIT":4500,"INVOICED":4500,"INVOICED_REMAINING":0,"INVOICE_APPROVED":0,"INVOICE_PAID":0,"INVOICE_REJECTED":0,"ORDERED":4500,"QC":4500,"QC_REMAINING":0,"READY_TO_SHIP":4500,"READY_TO_SHIP_REMAINING":0,"RECEIVED":4500,"REJECTED":0,"REQUESTED":0,"REQUESTED_REMAINING":0,"SCRAPPED":0},"supplier":{"orgId":"DESU1","orgName":"Supplier Org1","emailId":"","vendorCode":"","address":"Juhu Road","departmentId":""},"receiver":{"orgId":"DEOW1","orgName":"Buyer","emailId":"","vendorCode":"","address":"T-68-1","departmentId":""},"deliverBy":"2020-04-30T18:29:59Z","deliverByUnixTs":1588271399,"pricePerUnit":30,"qualityMeasure":"","reasonForRejection":"","taxApplicable":{"CGST":{"id":"","taxName":"CGST","taxRate":8,"taxAmount":10800,"isApplicable":true},"IGST":{"id":"","taxName":"","taxRate":0,"taxAmount":0,"isApplicable":false},"SGST":{"id":"","taxName":"SGST","taxRate":8,"taxAmount":10800,"isApplicable":true}},"items":[],"shopOrder":"","totalAmount":0}}}`)
	var result bytes.Buffer

	err := jsonlogic.Apply(logic, data, &result)

	fmt.Println(result.String())
	fmt.Println(err)
}


error :
 panic: interface conversion: interface {} is map[string]interface {}, not []interface {}

goroutine 1 [running]:
github.com/diegoholiveira/jsonlogic.getVar(0x154500, 0x40c178, 0x154e60, 0x43e3e0, 0x0, 0x154e60)
	/tmp/gopath790557694/pkg/mod/github.com/diegoholiveira/jsonlogic@v2.3.1+incompatible/vars.go:89 +0x740
github.com/diegoholiveira/jsonlogic.operation(0x40e053, 0x3, 0x154500, 0x40c178, 0x154e60, 0x43e3e0, 0x132500, 0x1c8f)
	/tmp/gopath790557694/pkg/mod/github.com/diegoholiveira/jsonlogic@v2.3.1+incompatible/jsonlogic.go:540 +0x1120
github.com/diegoholiveira/jsonlogic.apply(0x154e60, 0x43e3a0, 0x154e60, 0x43e3e0, 0x277801, 0x15d240)
	/tmp/gopath790557694/pkg/mod/github.com/diegoholiveira/jsonlogic@v2.3.1+incompatible/jsonlogic.go:708 +0x1e0
github.com/diegoholiveira/jsonlogic.parseValues(0x14d940, 0x40a0f0, 0x154e60, 0x43e3e0, 0x0, 0x1c00)
	/tmp/gopath790557694/pkg/mod/github.com/diegoholiveira/jsonlogic@v2.3.1+incompatible/jsonlogic.go:674 +0x260
github.com/diegoholiveira/jsonlogic.apply(0x154e60, 0x43e380, 0x154e60, 0x43e3e0, 0x277801, 0x16e9a7)
	/tmp/gopath790557694/pkg/mod/github.com/diegoholiveira/jsonlogic@v2.3.1+incompatible/jsonlogic.go:708 +0x1a0
github.com/diegoholiveira/jsonlogic.parseValues(0x14d940, 0x40a110, 0x154e60, 0x43e3e0, 0xfefc9a08, 0x0)
	/tmp/gopath790557694/pkg/mod/github.com/diegoholiveira/jsonlogic@v2.3.1+incompatible/jsonlogic.go:674 +0x260
github.com/diegoholiveira/jsonlogic.apply(0x154e60, 0x43e360, 0x154e60, 0x43e3e0, 0x277801, 0x8)
	/tmp/gopath790557694/pkg/mod/github.com/diegoholiveira/jsonlogic@v2.3.1+incompatible/jsonlogic.go:708 +0x1a0
github.com/diegoholiveira/jsonlogic.parseValues(0x14d940, 0x40a130, 0x154e60, 0x43e3e0, 0x40e0a0, 0x1010000)
	/tmp/gopath790557694/pkg/mod/github.com/diegoholiveira/jsonlogic@v2.3.1+incompatible/jsonlogic.go:674 +0x260
github.com/diegoholiveira/jsonlogic.apply(0x154e60, 0x43e340, 0x154e60, 0x43e3e0, 0x277801, 0x1c8f)
	/tmp/gopath790557694/pkg/mod/github.com/diegoholiveira/jsonlogic@v2.3.1+incompatible/jsonlogic.go:708 +0x1a0
github.com/diegoholiveira/jsonlogic.parseValues(0x14d940, 0x40a140, 0x154e60, 0x43e3e0, 0x16, 0x1c8f)
	/tmp/gopath790557694/pkg/mod/github.com/diegoholiveira/jsonlogic@v2.3.1+incompatible/jsonlogic.go:674 +0x260
github.com/diegoholiveira/jsonlogic.apply(0x154e60, 0x43e320, 0x154e60, 0x43e3e0, 0x1, 0x0)
	/tmp/gopath790557694/pkg/mod/github.com/diegoholiveira/jsonlogic@v2.3.1+incompatible/jsonlogic.go:708 +0x1a0
github.com/diegoholiveira/jsonlogic.Apply(0x1c0300, 0x43e2c0, 0x1c0300, 0x43e2e0, 0x1c0140, 0x43e300, 0x1, 0x4)
	/tmp/gopath790557694/pkg/mod/github.com/diegoholiveira/jsonlogic@v2.3.1+incompatible/jsonlogic.go:736 +0x220
main.main()
	/tmp/sandbox395415131/prog.go:17 +0x140
