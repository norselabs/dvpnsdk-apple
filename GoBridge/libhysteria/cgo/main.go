// C entry points of libhysteria, exported for the LibHysteria.xcframework c-archive.
//
// Conventions: functions returning char* return NULL on success or a malloc'd error message
// that the caller must release with LibhysteriaFree. LibhysteriaVersion's result must be freed too.
package main

/*
#include <stdlib.h>
*/
import "C"

import (
	"unsafe"

	"github.com/norselabs/libhysteria"
)

//export LibhysteriaStart
func LibhysteriaStart(configJSON *C.char) *C.char {
	if err := libhysteria.Start(C.GoString(configJSON)); err != nil {
		return C.CString(err.Error())
	}
	return nil
}

//export LibhysteriaStop
func LibhysteriaStop() *C.char {
	if err := libhysteria.Stop(); err != nil {
		return C.CString(err.Error())
	}
	return nil
}

//export LibhysteriaIsRunning
func LibhysteriaIsRunning() C.int {
	if libhysteria.IsRunning() {
		return 1
	}
	return 0
}

//export LibhysteriaVersion
func LibhysteriaVersion() *C.char {
	return C.CString(libhysteria.Version())
}

//export LibhysteriaFree
func LibhysteriaFree(p *C.char) {
	C.free(unsafe.Pointer(p))
}

func main() {}
