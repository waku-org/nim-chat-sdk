import std/[times, deques]
import chronos

type
  MessagePriority* = enum
    Optional = 0
    Normal = 1
    Critical = 2

  QueuedMessage*[T] = object
    messageId*: string
    msg*: T
    priority*: MessagePriority
    queuedAt*: float

  MessageSender*[T] = proc(messageId: string, msg: T): Future[bool] {.async.}

  RateLimitManager*[T] = ref object
    messageCount*: int = 100  # Default to 100 messages
    epochDurationSec*: int = 600  # Default to 10 minutes
    currentCount*: int
    currentEpoch*: int64
    criticalQueue*: Deque[QueuedMessage[T]]
    normalQueue*: Deque[QueuedMessage[T]]
    optionalQueue*: Deque[QueuedMessage[T]]
    sender*: MessageSender[T]
    isRunning*: bool
    sendTask*: Future[void]

proc getCurrentEpoch(epochDurationSec: int): int64 =
  int64(epochTime() / float(epochDurationSec))

proc newRateLimitManager*[T](messageCount: int, epochDurationSec: int, sender: MessageSender[T]): RateLimitManager[T] =
  RateLimitManager[T](
    messageCount: messageCount,
    epochDurationSec: epochDurationSec,
    currentCount: 0,
    currentEpoch: getCurrentEpoch(epochDurationSec),
    criticalQueue: initDeque[QueuedMessage[T]](),
    normalQueue: initDeque[QueuedMessage[T]](),
    optionalQueue: initDeque[QueuedMessage[T]](),
    sender: sender,
    isRunning: false
  )

proc updateEpochIfNeeded[T](manager: RateLimitManager[T]) =
  let newEpoch = getCurrentEpoch(manager.epochDurationSec)
  if newEpoch > manager.currentEpoch:
    manager.currentEpoch = newEpoch
    manager.currentCount = 0

proc getUsagePercent[T](manager: RateLimitManager[T]): float =
  if manager.messageCount == 0:
    return 1.0
  float(manager.currentCount) / float(manager.messageCount)

proc queueForSend*[T](manager: RateLimitManager[T], messageId: string, msg: T, priority: MessagePriority) =
  manager.updateEpochIfNeeded()
  
  let queuedMsg = QueuedMessage[T](
    messageId: messageId,
    msg: msg,
    priority: priority,
    queuedAt: epochTime()
  )
  
  let usagePercent = manager.getUsagePercent()
  
  if usagePercent >= 1.0:
    # Quota exhausted - queue critical on top, queue normal, drop optional
    case priority:
    of Critical:
      manager.criticalQueue.addLast(queuedMsg)
    of Normal:
      manager.normalQueue.addLast(queuedMsg)
    of Optional:
      discard  # Drop optional messages when quota exhausted
  elif usagePercent >= 0.7:
    # Low quota - send critical, queue normal, drop optional
    case priority:
    of Critical:
      manager.criticalQueue.addLast(queuedMsg)
    of Normal:
      manager.normalQueue.addLast(queuedMsg)
    of Optional:
      discard  # Drop optional messages when quota low
  else:
    # Normal operation - queue all messages
    case priority:
    of Critical:
      manager.criticalQueue.addLast(queuedMsg)
    of Normal:
      manager.normalQueue.addLast(queuedMsg)
    of Optional:
      manager.optionalQueue.addLast(queuedMsg)

proc getNextMessage[T](manager: RateLimitManager[T]): QueuedMessage[T] =
  # Priority order: Critical -> Normal -> Optional
  if manager.criticalQueue.len > 0:
    return manager.criticalQueue.popFirst()
  elif manager.normalQueue.len > 0:
    return manager.normalQueue.popFirst()
  elif manager.optionalQueue.len > 0:
    return manager.optionalQueue.popFirst()
  else:
    raise newException(ValueError, "No messages in queue")

proc hasMessages[T](manager: RateLimitManager[T]): bool =
  manager.criticalQueue.len > 0 or manager.normalQueue.len > 0 or manager.optionalQueue.len > 0

proc sendLoop*[T](manager: RateLimitManager[T]): Future[void] {.async.} =
  manager.isRunning = true
  
  while manager.isRunning:
    try:
      manager.updateEpochIfNeeded()
      
      while manager.hasMessages() and manager.currentCount < manager.messageCount:
        let msg = manager.getNextMessage()
        
        try:
          let sent = await manager.sender(msg.messageId, msg.msg)
          if sent:
            manager.currentCount += 1
          else:
            # Re-queue failed message at beginning of appropriate queue
            case msg.priority:
            of Critical:
              manager.criticalQueue.addFirst(msg)
            of Normal:
              manager.normalQueue.addFirst(msg)
            of Optional:
              manager.optionalQueue.addFirst(msg)
            break  # Stop trying to send more messages if one fails
        except:
          # Re-queue on exception
          case msg.priority:
          of Critical:
            manager.criticalQueue.addFirst(msg)
          of Normal:
            manager.normalQueue.addFirst(msg)
          of Optional:
            manager.optionalQueue.addFirst(msg)
          break
        
        # Small delay between messages TODO not sure if needed
        await sleepAsync(chronos.milliseconds(10))
      
      # Wait before next processing cycle TODO not completely sure if this is the way
      await sleepAsync(chronos.milliseconds(100))
    except CancelledError:
      break
    except:
      await sleepAsync(chronos.seconds(1))  # Wait longer on error

proc start*[T](manager: RateLimitManager[T]): Future[void] {.async.} =
  if not manager.isRunning:
    manager.sendTask = manager.sendLoop()

proc stop*[T](manager: RateLimitManager[T]): Future[void] {.async.} =
  if manager.isRunning:
    manager.isRunning = false
    if not manager.sendTask.isNil:
      manager.sendTask.cancelSoon()
      try:
        await manager.sendTask
      except CancelledError:
        discard

proc getQueueStatus*[T](manager: RateLimitManager[T]): tuple[critical: int, normal: int, optional: int, total: int] =
  (
    critical: manager.criticalQueue.len,
    normal: manager.normalQueue.len,
    optional: manager.optionalQueue.len,
    total: manager.criticalQueue.len + manager.normalQueue.len + manager.optionalQueue.len
  )

proc getCurrentQuota*[T](manager: RateLimitManager[T]): tuple[total: int, used: int, remaining: int] =
  (
    total: manager.messageCount,
    used: manager.currentCount,
    remaining: max(0, manager.messageCount - manager.currentCount)
  )