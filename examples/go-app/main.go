package main

import (
	"fmt"
	"log"
	"sync"

	chatsdk "github.com/waku-org/nim-chat-sdk/bindings/go-bindings"
)

// SimpleStore implements the chatsdk.Store interface with in-memory storage
type SimpleStore struct {
	messages map[string]string
	mu       sync.RWMutex
}

// NewSimpleStore creates a new SimpleStore instance
func NewSimpleStore() *SimpleStore {
	return &SimpleStore{
		messages: make(map[string]string),
	}
}

// StoreMessage stores a message with the given ID
func (s *SimpleStore) StoreMessage(id, message string) bool {
	s.mu.Lock()
	defer s.mu.Unlock()

	fmt.Printf("📦 Storing message [%s]: %s\n", id, message)
	s.messages[id] = message
	return true
}

// GetMessage retrieves a message by ID
func (s *SimpleStore) GetMessage(id string) string {
	s.mu.RLock()
	defer s.mu.RUnlock()

	message, exists := s.messages[id]
	if exists {
		fmt.Printf("📤 Retrieved message [%s]: %s\n", id, message)
		return message
	}
	fmt.Printf("❌ Message not found [%s]\n", id)
	return ""
}

// ListAllMessages shows all stored messages
func (s *SimpleStore) ListAllMessages() {
	s.mu.RLock()
	defer s.mu.RUnlock()

	fmt.Println("\n📋 All stored messages:")
	if len(s.messages) == 0 {
		fmt.Println("  (no messages stored)")
		return
	}

	for id, message := range s.messages {
		fmt.Printf("  [%s]: %s\n", id, message)
	}
}

func main() {
	fmt.Println("ChatSDK Go Example - Enhanced with Storage")
	fmt.Println("==========================================")

	// Test 1: Original standalone API (backward compatibility)
	fmt.Println("\n🔸 Testing standalone API (backward compatibility):")
	messages := []string{
		"Hello from standalone API!",
		"This message won't be stored",
	}

	for i, msg := range messages {
		fmt.Printf("Sending standalone message #%d: %s\n", i+1, msg)
		if err := chatsdk.SendMessage(msg); err != nil {
			log.Printf("Error: %v", err)
		} else {
			fmt.Println("✓ Message sent successfully")
		}
	}

	// Test 2: ChatSDK object with Store interface
	fmt.Println("\n🔸 Testing ChatSDK object with Store interface:")

	// Create a store implementation
	store := NewSimpleStore()

	// Create ChatSDK instance with the store
	sdk, err := chatsdk.NewChatSDK(store)
	if err != nil {
		log.Fatalf("Failed to create ChatSDK: %v", err)
	}
	defer sdk.Close()

	// Send messages with IDs (they will be stored)
	testMessages := map[string]string{
		"msg1": "Hello from ChatSDK object!",
		"msg2": "This message will be stored and can be retrieved",
		"msg3": "Nim ❤️ Go with storage interface working!",
		"msg4": "Another stored message with a longer ID",
	}

	fmt.Println("\n📤 Sending messages with storage:")
	for id, message := range testMessages {
		fmt.Printf("Sending message [%s]: %s\n", id, message)
		if err := sdk.SendMessage(id, message); err != nil {
			log.Printf("Error sending message: %v", err)
		} else {
			fmt.Println("✓ Message sent and stored successfully")
		}
		fmt.Println()
	}

	// Test message retrieval
	fmt.Println("\n📥 Testing message retrieval:")
	testIDs := []string{"msg1", "msg2", "msg3", "msg4", "nonexistent"}

	for _, id := range testIDs {
		fmt.Printf("Retrieving message [%s]...\n", id)
		message, err := sdk.GetMessage(id)
		if err != nil {
			log.Printf("Error retrieving message: %v", err)
		} else if message != "" {
			fmt.Printf("✓ Found: %s\n", message)
		} else {
			fmt.Printf("❌ Message not found\n")
		}
		fmt.Println()
	}

	// Show all stored messages
	store.ListAllMessages()

	fmt.Println("\n✅ Example completed successfully!")
}
