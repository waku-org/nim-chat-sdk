import math, times, sequtils, strutils, options
import nimcrypto # For Keccak256 hashing
import results
import leopard # Import nim-leopard for Reed-Solomon
import chronicles

# External dependencies (still needed)
# import protobuf # Nim protobuf library (e.g., protobuf-nim)

# SegmentMessage type (unchanged)
type
  SegmentMessage* = ref object
    entireMessageHash*: seq[byte]
    index*: uint32
    segmentsCount*: uint32
    paritySegmentIndex*: uint32
    paritySegmentsCount*: uint32
    payload*: seq[byte]


# Placeholder types (unchanged)
type
  WakuNewMessage* = object
    payload*: seq[byte]
    # Add other fields as needed

  StatusMessage* = object
    transportLayer*: TransportLayer

  TransportLayer* = object
    hash*: seq[byte]
    payload*: seq[byte]
    sigPubKey*: seq[byte]

  Persistence = object
    completedMessages: Table[seq[byte], bool]  # Mock storage for completed message hashes
    segments: Table[(seq[byte], seq[byte]), seq[SegmentMessage]]  # Stores segments by (hash, sigPubKey)

# Error definitions (unchanged)
const
  ErrMessageSegmentsIncomplete = "message segments incomplete"
  ErrMessageSegmentsAlreadyCompleted = "message segments already completed"
  ErrMessageSegmentsInvalidCount = "invalid segments count"
  ErrMessageSegmentsHashMismatch = "hash of entire payload does not match"
  ErrMessageSegmentsInvalidParity = "invalid parity segments"

# Constants (unchanged)
const
  SegmentsParityRate = 0.125
  SegmentsReedsolomonMaxCount = 256


# Validation methods (unchanged)
proc isValid*(s: SegmentMessage): bool =
  s.segmentsCount >= 2 or s.paritySegmentsCount > 0

proc isParityMessage*(s: SegmentMessage): bool =
  s.segmentsCount == 0 and s.paritySegmentsCount > 0

# MessageSender type (unchanged)
type
  MessageSender* = ref object
    messaging*: Messaging
    persistence*: Persistence

  Messaging* = object
    maxMessageSize*: int

proc initPersistence*(): Persistence =
  Persistence(
    completedMessages: initTable[seq[byte], bool](),
    segments: initTable[(seq[byte], seq[byte]), seq[SegmentMessage]]()
  )

proc isMessageAlreadyCompleted(p: Persistence, hash: seq[byte]): Result[bool, string] =
  return ok(p.completedMessages.getOrDefault(hash, false))

proc saveMessageSegment(p: var Persistence, segment: SegmentMessage, sigPubKey: seq[byte], timestamp: int64): Result[void, string] =
  let key = (segment.entireMessageHash, sigPubKey)
  # Initialize or append to the segments list
  if not p.segments.hasKey(key):
    p.segments[key] = @[]
  p.segments[key].add(segment)
  return ok()

proc getMessageSegments(p: Persistence, hash: seq[byte], sigPubKey: seq[byte]): Result[seq[SegmentMessage], string] =
  let key = (hash, sigPubKey)
  return ok(p.segments.getOrDefault(key, @[]))

proc completeMessageSegments(p: var Persistence, hash: seq[byte], sigPubKey: seq[byte], timestamp: int64): Result[void, string] =
  p.completedMessages[hash] = true
  return ok()

# Replicate message (unchanged)
proc replicateMessageWithNewPayload(message: WakuNewMessage, payload: seq[byte]): Result[WakuNewMessage, string] =
  var copiedMessage = WakuNewMessage(payload: payload)
  return ok(copiedMessage)

proc protoMarshal(msg: SegmentMessage): Result[seq[byte], string] =
  # Fake serialization (index + payload length) TODO
  return ok(@[byte(msg.index)] & msg.payload)

proc protoUnmarshal(data: seq[byte], msg: var SegmentMessage): Result[void, string] =
  # Fake deserialization (reconstruct index and payload)
  if data.len < 1:
    return err("data too short")
  msg.index = uint32(data[0])
  msg.payload = data[1..^1]
  msg.segmentsCount = 2
  msg.entireMessageHash = @[byte 1, 2, 3]  # Dummy hash
  return ok()

# Segment message into smaller chunks (updated with nim-leopard)
proc segmentMessageInternal(newMessage: WakuNewMessage, segmentSize: int): Result[seq[WakuNewMessage], string] =
  if newMessage.payload.len <= segmentSize:
    return ok(@[newMessage])

  let entireMessageHash = keccak256.digest(newMessage.payload)
  let entirePayloadSize = newMessage.payload.len

  let segmentsCount = int(ceil(entirePayloadSize.float / segmentSize.float))
  let paritySegmentsCount = int(floor(segmentsCount.float * SegmentsParityRate))

  var segmentPayloads = newSeq[seq[byte]](segmentsCount + paritySegmentsCount)
  var segmentMessages = newSeq[WakuNewMessage](segmentsCount)

  for i in 0..<segmentsCount:
    let start = i * segmentSize
    var endIndex = start + segmentSize
    if endIndex > entirePayloadSize:
      endIndex = entirePayloadSize

    let segmentPayload = newMessage.payload[start..<endIndex]
    let segmentWithMetadata = SegmentMessage(
      entireMessageHash: entireMessageHash.data.toSeq,
      index: uint32(i),
      segmentsCount: uint32(segmentsCount),
      payload: segmentPayload
    )

    let marshaledSegment = protoMarshal(segmentWithMetadata)
    if marshaledSegment.isErr:
      return err("failed to marshal SegmentMessage: " & marshaledSegment.error)

    let segmentMessage = replicateMessageWithNewPayload(newMessage, marshaledSegment.get())
    if segmentMessage.isErr:
      return err("failed to replicate message: " & segmentMessage.error)

    segmentPayloads[i] = segmentPayload
    segmentMessages[i] = segmentMessage.get()

  # Skip Reed-Solomon if parity segments are 0 or total exceeds max count
  if paritySegmentsCount == 0 or (segmentsCount + paritySegmentsCount) > SegmentsReedsolomonMaxCount:
    return ok(segmentMessages)

  # Align last segment payload for Reed-Solomon (leopard requires fixed-size shards)
  let lastSegmentPayload = segmentPayloads[segmentsCount-1]
  segmentPayloads[segmentsCount-1] = newSeq[byte](segmentSize)
  segmentPayloads[segmentsCount-1][0..<lastSegmentPayload.len] = lastSegmentPayload

  # Allocate space for parity shards
  for i in segmentsCount..<(segmentsCount + paritySegmentsCount):
    segmentPayloads[i] = newSeq[byte](segmentSize)

  # Use nim-leopard for Reed-Solomon encoding
  var data = segmentPayloads[0..<segmentsCount]
  var parity = segmentPayloads[segmentsCount..<(segmentsCount + paritySegmentsCount)]
  var encoderRes = LeoEncoder.init(segmentSize, segmentsCount, paritySegmentsCount)
  if encoderRes.isErr:
    return err("failed to initialize encoder: " & $encoderRes.error)
  var encoder = encoderRes.get
  let encodeResult = encoder.encode(data, parity)
  if encodeResult.isErr:
    return err("failed to encode segments with leopard: " & $encodeResult.error)

  # Create parity messages
  for i in segmentsCount..<(segmentsCount + paritySegmentsCount):
    let parityIndex = i - segmentsCount
    let segmentWithMetadata = SegmentMessage(
      entireMessageHash: entireMessageHash.data.toSeq,
      segmentsCount: 0,
      paritySegmentIndex: uint32(parityIndex),
      paritySegmentsCount: uint32(paritySegmentsCount),
      payload: segmentPayloads[i]
    )

    let marshaledSegment = protoMarshal(segmentWithMetadata)
    if marshaledSegment.isErr:
      return err("failed to marshal parity SegmentMessage: " & marshaledSegment.error)

    let segmentMessage = replicateMessageWithNewPayload(newMessage, marshaledSegment.get())
    if segmentMessage.isErr:
      return err("failed to replicate parity message: " & segmentMessage.error)

    segmentMessages.add(segmentMessage.get())

  return ok(segmentMessages)

# Handle SegmentationLayerV2 (updated with nim-leopard)
proc handleSegmentationLayerV2*(s: MessageSender, message: var StatusMessage): Result[void, string] =
  logScope:
    site = "handleSegmentationLayerV2"
    hash = message.transportLayer.hash.toHex

  var segmentMessage = SegmentMessage()
  let unmarshalResult = protoUnmarshal(message.transportLayer.payload, segmentMessage)
  if unmarshalResult.isErr:
    return err("failed to unmarshal SegmentMessage: " & unmarshalResult.error)

  debug "handling message segment",
    "EntireMessageHash" = segmentMessage.entireMessageHash.toHex,
    "Index" = $segmentMessage.index,
    "SegmentsCount" = $segmentMessage.segmentsCount,
    "ParitySegmentIndex" = $segmentMessage.paritySegmentIndex,
    "ParitySegmentsCount" = $segmentMessage.paritySegmentsCount
  
  # TODO here use the mock function, real function should be used together with the persistence layer
  let alreadyCompleted = s.persistence.isMessageAlreadyCompleted(segmentMessage.entireMessageHash)
  if alreadyCompleted.isErr:
    return err(alreadyCompleted.error)
  if alreadyCompleted.get():
    return err(ErrMessageSegmentsAlreadyCompleted)

  if not segmentMessage.isValid():
    return err(ErrMessageSegmentsInvalidCount)

  let saveResult = s.persistence.saveMessageSegment(segmentMessage, message.transportLayer.sigPubKey, getTime().toUnix)
  if saveResult.isErr:
    return err(saveResult.error)

  let segments = s.persistence.getMessageSegments(segmentMessage.entireMessageHash, message.transportLayer.sigPubKey)
  if segments.isErr:
    return err(segments.error)

  if segments.get().len == 0:
    return err("unexpected state: no segments found after save operation")

  let firstSegmentMessage = segments.get()[0]
  let lastSegmentMessage = segments.get()[^1]

  if firstSegmentMessage.isParityMessage() or segments.get().len != int(firstSegmentMessage.segmentsCount):
    return err(ErrMessageSegmentsIncomplete)

  var payloads = newSeq[seq[byte]](firstSegmentMessage.segmentsCount + lastSegmentMessage.paritySegmentsCount)
  let payloadSize = firstSegmentMessage.payload.len

  let restoreUsingParityData = lastSegmentMessage.isParityMessage()
  if not restoreUsingParityData:
    for i, segment in segments.get():
      payloads[i] = segment.payload
  else:
    var lastNonParitySegmentPayload: seq[byte]
    for segment in segments.get():
      if not segment.isParityMessage():
        if segment.index == firstSegmentMessage.segmentsCount - 1:
          payloads[segment.index] = newSeq[byte](payloadSize)
          payloads[segment.index][0..<segment.payload.len] = segment.payload
          lastNonParitySegmentPayload = segment.payload
        else:
          payloads[segment.index] = segment.payload
      else:
        payloads[firstSegmentMessage.segmentsCount + segment.paritySegmentIndex] = segment.payload

    # Use nim-leopard for Reed-Solomon reconstruction
    let decoderRes = LeoDecoder.init(payloadSize, int(firstSegmentMessage.segmentsCount), int(lastSegmentMessage.paritySegmentsCount))
    if decoderRes.isErr:
      return err("failed to initialize LeoDecoder: " & $decoderRes.error)
    var decoder = decoderRes.get()
    var data = payloads[0..<int(firstSegmentMessage.segmentsCount)]
    var parity = payloads[int(firstSegmentMessage.segmentsCount)..<(int(firstSegmentMessage.segmentsCount) + int(lastSegmentMessage.paritySegmentsCount))]
    var recovered = newSeq[seq[byte]](int(firstSegmentMessage.segmentsCount))  # Allocate for recovered shards
    for i in 0..<int(firstSegmentMessage.segmentsCount):
      recovered[i] = newSeq[byte](payloadSize)
    let reconstructResult = decoder.decode(data, parity, recovered)
    if reconstructResult.isErr:
      return err("failed to reconstruct payloads with leopard: " & $reconstructResult.error)

    # Verify by checking hash (leopard doesn't have a direct verify function)
    var tempPayload = newSeq[byte]()
    for i in 0..<int(firstSegmentMessage.segmentsCount):
      tempPayload.add(payloads[i])
    let tempHash = keccak256.digest(tempPayload)
    if tempHash.data != segmentMessage.entireMessageHash:
      return err(ErrMessageSegmentsInvalidParity)

    if lastNonParitySegmentPayload.len > 0:
      payloads[firstSegmentMessage.segmentsCount - 1] = lastNonParitySegmentPayload

  # Combine payload
  var entirePayload = newSeq[byte]()
  for i in 0..<int(firstSegmentMessage.segmentsCount):
    entirePayload.add(payloads[i])

  # Sanity check
  let entirePayloadHash = keccak256.digest(entirePayload)
  if entirePayloadHash.data != segmentMessage.entireMessageHash:
    return err(ErrMessageSegmentsHashMismatch)

  let completeResult = s.persistence.completeMessageSegments(segmentMessage.entireMessageHash, message.transportLayer.sigPubKey, getTime().toUnix)
  if completeResult.isErr:
    return err(completeResult.error)

  message.transportLayer.payload = entirePayload
  return ok()

# Other procs (unchanged)
proc handleSegmentationLayerV1*(s: MessageSender, message: StatusMessage): Result[void, string] =
  # Same as previous translation
  discard

proc cleanupSegments*(s: MessageSender): Result[void, string] =
  # Same as previous translation
  discard

# SegmentMessage proc (unchanged)
proc segmentMessage*(s: MessageSender, newMessage: WakuNewMessage): Result[seq[WakuNewMessage], string] =
  let segmentSize = s.messaging.maxMessageSize div 4 * 3
  let segmentResult = segmentMessageInternal(newMessage, segmentSize)
  if segmentResult.isErr:
    return err("segmentMessage failed: " & result.error)
  let messages = result.get()
  debug "message segmented", "segments" = $messages.len
  return ok(messages)

proc demoRounding() =
  let x = 3.7
  let y = -3.7

  echo "ceil(", x, ") = ", ceil(x)   # Rounds up
  echo "floor(", x, ") = ", floor(x) # Rounds down
  echo "round(", x, ") = ", round(x) # Rounds to nearest integer
  echo "trunc(", x, ") = ", trunc(x) # Truncates decimal part
  echo "ceil(", y, ") = ", ceil(y)
  echo "floor(", y, ") = ", floor(y)

  let
    bufSize = 64  # byte count per buffer, must be a multiple of 64
    buffers = 239 # number of data symbols
    parity = 17   # number of parity symbols

  var
    encoderRes = LeoEncoder.init(bufSize, buffers, parity)
    decoderRes = LeoDecoder.init(bufSize, buffers, parity)

  assert encoderRes.isOk
  assert decoderRes.isOk


when isMainModule:
  demoRounding()

proc add2*(x, y: int): int =
  ## Adds two numbers together.
  return x + y
