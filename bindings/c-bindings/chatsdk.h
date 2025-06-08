#ifndef CHATSDK_H
#define CHATSDK_H

#ifdef __cplusplus
extern "C" {
#endif

// Forward declaration for ChatSDK
typedef struct ChatSDK ChatSDK;

// Storage interface function pointer types
typedef int (*StoreMessageProc)(const char* id, const char* message, void* userData);
typedef const char* (*GetMessageProc)(const char* id, void* userData);

/**
 * Send a message through the ChatSDK (standalone version)
 * @param message The message to send as a null-terminated string
 * @return 0 on success, non-zero on error
 */
int sendMessageCString(const char* message);

/**
 * Create a new ChatSDK instance with storage callbacks
 * @param storeProc Function pointer for storing messages
 * @param getProc Function pointer for retrieving messages
 * @param userData Optional user data pointer
 * @return Pointer to ChatSDK instance or NULL on error
 */
ChatSDK* newChatSDKC(StoreMessageProc storeProc, GetMessageProc getProc, void* userData);

/**
 * Free a ChatSDK instance
 * @param sdk Pointer to ChatSDK instance to free
 */
void freeChatSDKC(ChatSDK* sdk);

/**
 * Send a message through a ChatSDK instance
 * @param sdk Pointer to ChatSDK instance
 * @param id Message ID
 * @param message The message to send
 * @return 0 on success, non-zero on error
 */
int sendMessageSDKC(ChatSDK* sdk, const char* id, const char* message);

/**
 * Get a message from a ChatSDK instance
 * @param sdk Pointer to ChatSDK instance
 * @param id Message ID to retrieve
 * @return Message string (caller must call freeCString) or NULL if not found
 */
const char* getMessageSDKC(ChatSDK* sdk, const char* id);

/**
 * Free a C string allocated by the library
 * @param str String to free
 */
void freeCString(const char* str);

#ifdef __cplusplus
}
#endif

#endif // CHATSDK_H 