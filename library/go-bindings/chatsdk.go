package chatsdk

/*
#cgo CFLAGS: -I../c-bindings
#cgo LDFLAGS: -L../c-bindings -lchatsdk
#include "chatsdk.h"
#include <stdlib.h>

// Forward declarations for the Go callback functions
int goStoreMessage(const char* id, const char* message, void* userData);
const char* goGetMessage(const char* id, void* userData);
*/
import "C"
import (
	"errors"
	"runtime"
	"sync"
	"unsafe"
)

// Store interface that Go implementations must satisfy
type Store interface {
	StoreMessage(id, message string) bool
	GetMessage(id string) string
}

// ChatSDK represents a chat SDK instance with storage capabilities
type ChatSDK struct {
	cSDK   *C.ChatSDK
	store  Store
	closed bool
	mu     sync.RWMutex
}

// Global registry to map C callback calls back to Go Store implementations
var (
	storeRegistry = make(map[uintptr]Store)
	registryMu    sync.RWMutex
	nextID        uintptr = 1
)

// SendMessage sends a message through the ChatSDK (standalone version)
func SendMessage(message string) error {
	cMessage := C.CString(message)
	defer C.free(unsafe.Pointer(cMessage))

	result := C.sendMessageCString(cMessage)
	if result != 0 {
		return errors.New("failed to send message")
	}

	return nil
}

// NewChatSDK creates a new ChatSDK instance with the provided store implementation
func NewChatSDK(store Store) (*ChatSDK, error) {
	if store == nil {
		return nil, errors.New("store cannot be nil")
	}

	// Register the store implementation
	registryMu.Lock()
	storeID := nextID
	nextID++
	storeRegistry[storeID] = store
	registryMu.Unlock()

	// Create the C SDK instance with callback function pointers
	userData := unsafe.Pointer(uintptr(storeID))
	cSDK := C.newChatSDKC(
		C.StoreMessageProc(C.goStoreMessage),
		C.GetMessageProc(C.goGetMessage),
		userData,
	)

	if cSDK == nil {
		// Clean up registry on failure
		registryMu.Lock()
		delete(storeRegistry, storeID)
		registryMu.Unlock()
		return nil, errors.New("failed to create ChatSDK instance")
	}

	sdk := &ChatSDK{
		cSDK:  cSDK,
		store: store,
	}

	// Set finalizer to ensure cleanup
	runtime.SetFinalizer(sdk, (*ChatSDK).Close)

	return sdk, nil
}

// SendMessage sends a message through this ChatSDK instance
func (sdk *ChatSDK) SendMessage(id, message string) error {
	sdk.mu.RLock()
	defer sdk.mu.RUnlock()

	if sdk.closed {
		return errors.New("ChatSDK instance is closed")
	}

	cID := C.CString(id)
	cMessage := C.CString(message)
	defer C.free(unsafe.Pointer(cID))
	defer C.free(unsafe.Pointer(cMessage))

	result := C.sendMessageSDKC(sdk.cSDK, cID, cMessage)
	if result != 0 {
		return errors.New("failed to send message")
	}

	return nil
}

// GetMessage retrieves a message by ID through this ChatSDK instance
func (sdk *ChatSDK) GetMessage(id string) (string, error) {
	sdk.mu.RLock()
	defer sdk.mu.RUnlock()

	if sdk.closed {
		return "", errors.New("ChatSDK instance is closed")
	}

	cID := C.CString(id)
	defer C.free(unsafe.Pointer(cID))

	cResult := C.getMessageSDKC(sdk.cSDK, cID)
	if cResult == nil {
		return "", nil // Message not found
	}

	result := C.GoString(cResult)
	C.freeCString(cResult) // Free the string allocated by Nim
	return result, nil
}

// Close frees the ChatSDK instance and cleans up resources
func (sdk *ChatSDK) Close() error {
	sdk.mu.Lock()
	defer sdk.mu.Unlock()

	if sdk.closed {
		return nil
	}

	if sdk.cSDK != nil {
		C.freeChatSDKC(sdk.cSDK)
		sdk.cSDK = nil
	}

	sdk.closed = true
	runtime.SetFinalizer(sdk, nil)
	return nil
}

// getStoreFromUserData retrieves a Store implementation from userData pointer
func getStoreFromUserData(userData unsafe.Pointer) Store {
	if userData == nil {
		return nil
	}

	storeID := uintptr(userData)
	registryMu.RLock()
	store := storeRegistry[storeID]
	registryMu.RUnlock()
	return store
}
