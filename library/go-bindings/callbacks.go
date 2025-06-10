package chatsdk

/*
#include <stdlib.h>
*/
import "C"
import (
	"unsafe"
)

// goStoreMessage is called from C to store a message using the Go Store interface
//
//export goStoreMessage
func goStoreMessage(cID *C.char, cMessage *C.char, userData unsafe.Pointer) C.int {
	if cID == nil || cMessage == nil {
		return 1 // Error
	}

	store := getStoreFromUserData(userData)
	if store == nil {
		return 1 // Error
	}

	id := C.GoString(cID)
	message := C.GoString(cMessage)

	success := store.StoreMessage(id, message)
	if success {
		return 0 // Success
	}
	return 1 // Error
}

// goGetMessage is called from C to retrieve a message using the Go Store interface
//
//export goGetMessage
func goGetMessage(cID *C.char, userData unsafe.Pointer) *C.char {
	if cID == nil {
		return nil
	}

	store := getStoreFromUserData(userData)
	if store == nil {
		return nil
	}

	id := C.GoString(cID)
	message := store.GetMessage(id)

	if message == "" {
		return nil
	}

	// Allocate C string - Nim side will free this
	return C.CString(message)
}
