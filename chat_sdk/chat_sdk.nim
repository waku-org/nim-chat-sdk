import std/[times]

# Storage interface function pointer types
type
  StoreMessageProc* = proc(id: cstring, message: cstring, userData: pointer): cint {.cdecl.}
  GetMessageProc* = proc(id: cstring, userData: pointer): cstring {.cdecl.}

# ChatSDK object
type
  ChatSDK* = object
    storeCallback: StoreMessageProc
    getCallback: GetMessageProc
    userData: pointer  # For Go-side data if needed

# Create a new ChatSDK instance
proc newChatSDK*(storeProc: StoreMessageProc, getProc: GetMessageProc, userData: pointer = nil): ChatSDK =
  ChatSDK(
    storeCallback: storeProc,
    getCallback: getProc,
    userData: userData
  )

# Send message method for ChatSDK
proc sendMessage*(sdk: ChatSDK, id: string, message: string): bool =
  ## Sends a message by printing it to stdout with timestamp and storing it
  let timestamp = now()
  echo "[", timestamp.format("yyyy-MM-dd HH:mm:ss"), "] ChatSDK: ", message
  
  # Store the message using the provided storage interface
  if sdk.storeCallback != nil:
    let storeResult = sdk.storeCallback(cstring(id), cstring(message), sdk.userData)
    return storeResult == 0
  return false

# Get message method for ChatSDK
proc getMessage*(sdk: ChatSDK, id: string): string =
  ## Gets a message using the provided storage interface
  if sdk.getCallback != nil:
    let messageResult = sdk.getCallback(cstring(id), sdk.userData)
    if messageResult != nil:
      return $messageResult
  return ""

# Original standalone sendMessage for backward compatibility
proc sendMessage*(message: string) =
  ## Sends a message by printing it to stdout with timestamp
  let timestamp = now()
  echo "[", timestamp.format("yyyy-MM-dd HH:mm:ss"), "] ChatSDK: ", message

# C-compatible wrappers
proc sendMessageCString*(message: cstring): cint {.exportc, dynlib.} =
  ## C-compatible wrapper for standalone sendMessage
  try:
    sendMessage($message)
    return 0  # Success
  except:
    return 1  # Error

proc newChatSDKC*(storeProc: StoreMessageProc, getProc: GetMessageProc, userData: pointer = nil): ptr ChatSDK {.exportc, dynlib.} =
  ## C-compatible wrapper to create a new ChatSDK instance
  try:
    let sdk = newChatSDK(storeProc, getProc, userData)
    let sdkPtr = cast[ptr ChatSDK](alloc(sizeof(ChatSDK)))
    sdkPtr[] = sdk
    return sdkPtr
  except:
    return nil

proc freeChatSDKC*(sdk: ptr ChatSDK) {.exportc, dynlib.} =
  ## C-compatible wrapper to free ChatSDK instance
  if sdk != nil:
    dealloc(sdk)

proc sendMessageSDKC*(sdk: ptr ChatSDK, id: cstring, message: cstring): cint {.exportc, dynlib.} =
  ## C-compatible wrapper for ChatSDK sendMessage
  try:
    if sdk == nil:
      return 1
    let success = sdk[].sendMessage($id, $message)
    return if success: 0 else: 1
  except:
    return 1

proc getMessageSDKC*(sdk: ptr ChatSDK, id: cstring): cstring {.exportc, dynlib.} =
  ## C-compatible wrapper for ChatSDK getMessage
  try:
    if sdk == nil:
      return nil
    let message = sdk[].getMessage($id)  # Convert cstring to string for internal method
    if message.len > 0:
      # Allocate C string - caller must free
      let cStr = cast[cstring](alloc(message.len + 1))
      copyMem(cStr, cstring(message), message.len + 1)
      return cStr
    return nil
  except:
    return nil

proc freeCString*(str: cstring) {.exportc, dynlib.} =
  ## Free a C string allocated by the library
  if str != nil:
    dealloc(str)

# Export the module for C bindings
when isMainModule:
  sendMessage("Test message from Nim!") 


# This is just an example to get you started. A typical library package
# exports the main API in this file. Note that you cannot rename this file
# but you can remove it if you wish.

proc add*(x, y: int): int =
  ## Adds two numbers together.
  return x + y
