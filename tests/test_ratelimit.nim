{.used.}

import std/[sequtils, times, random], testutils/unittests
import ../ratelimit/ratelimit
import chronos

randomize()

# Test message types
type
  TestMessage = object
    content: string
    id: int

suite "Rate Limit Manager":
  setup:
    ## Given
    let epochDuration = 60
    var sentMessages: seq[string]
    
    proc testSender(messageId: string, msg: string): Future[bool] {.async.} =
      sentMessages.add(msg)
      await sleepAsync(chronos.milliseconds(10))
      return true

  asyncTest "basic message queueing and sending":
    ## Given
    let capacity = 10
    var manager = newRateLimitManager(capacity, epochDuration, testSender)
    await manager.start()
    
    ## When
    manager.queueForSend("msg1", "Hello", Critical)
    manager.queueForSend("msg2", "World", Normal)
    
    await sleepAsync(chronos.milliseconds(200))
    await manager.stop()
    
    ## Then
    check:
      sentMessages.len == 2
      sentMessages[0] == "Hello"
      sentMessages[1] == "World"

  asyncTest "priority ordering - critical first, then normal, then optional":
    ## Given
    let capacity = 10
    var manager = newRateLimitManager(capacity, epochDuration, testSender)
    await manager.start()
    
    ## When - queue messages in mixed priority order
    manager.queueForSend("normal1", "Normal1", Normal)
    manager.queueForSend("critical1", "Critical1", Critical)
    manager.queueForSend("optional1", "Optional1", Optional)
    manager.queueForSend("critical2", "Critical2", Critical)
    manager.queueForSend("normal2", "Normal2", Normal)
    
    await sleepAsync(chronos.milliseconds(300))
    await manager.stop()
    
    ## Then - critical messages should be sent first
    check:
      sentMessages.len == 5
      sentMessages[0] == "Critical1"  # First critical
      sentMessages[1] == "Critical2"  # Second critical
      sentMessages[2] == "Normal1"    # Then normal messages
      sentMessages[3] == "Normal2"
      sentMessages[4] == "Optional1"  # Finally optional

  asyncTest "rate limiting - respects message quota per epoch":
    ## Given
    let capacity = 3  # Only 3 messages allowed
    var manager = newRateLimitManager(capacity, epochDuration, testSender)
    await manager.start()
    
    ## When - queue more messages than the limit
    for i in 1..5:
      manager.queueForSend("msg" & $i, "Message" & $i, Normal)
    
    await sleepAsync(chronos.milliseconds(300))
    
    ## Then
    let quota = manager.getCurrentQuota()
    let queueStatus = manager.getQueueStatus()
    
    check:
      quota.used == 3
      quota.remaining == 0
      sentMessages.len == 3
      queueStatus.total == 2  # 2 messages should be queued
    
    await manager.stop()

  asyncTest "optional message dropping at high usage":
    ## Given
    let capacity = 10
    var manager = newRateLimitManager(capacity, epochDuration, testSender)
    await manager.start()
    
    # Fill to 80% capacity to trigger optional dropping
    for i in 1..8:
      manager.queueForSend("fill" & $i, "Fill" & $i, Normal)
    
    await sleepAsync(chronos.milliseconds(200))
    
    ## When - add messages at high usage
    manager.queueForSend("critical", "Critical", Critical)
    manager.queueForSend("normal", "Normal", Normal)
    manager.queueForSend("optional", "Optional", Optional)  # Should be dropped
    
    await sleepAsync(chronos.milliseconds(200))
    
    ## Then
    let quota = manager.getCurrentQuota()
    let optionalSent = sentMessages.anyIt(it == "Optional")
    
    check:
      quota.used == 10
      not optionalSent  # Optional message should not be sent
    
    await manager.stop()

  asyncTest "quota tracking - accurate total, used, and remaining counts":
    ## Given
    let capacity = 5
    var manager = newRateLimitManager(capacity, epochDuration, testSender)
    await manager.start()
    
    ## When - initially no messages sent
    let initialQuota = manager.getCurrentQuota()
    
    ## Then - should show full quota available
    check:
      initialQuota.total == 5
      initialQuota.used == 0
      initialQuota.remaining == 5
    
    ## When - send some messages
    manager.queueForSend("msg1", "Message1", Normal)
    manager.queueForSend("msg2", "Message2", Normal)
    
    await sleepAsync(chronos.milliseconds(200))
    
    ## Then - quota should be updated
    let afterQuota = manager.getCurrentQuota()
    check:
      afterQuota.used == 2
      afterQuota.remaining == 3
    
    await manager.stop()

  asyncTest "queue status tracking - by priority levels":
    ## Given
    let capacity = 2  # Small limit to force queueing
    var manager = newRateLimitManager(capacity, epochDuration, testSender)
    await manager.start()
    
    ## When - fill quota and add more messages
    manager.queueForSend("msg1", "Message1", Critical)
    manager.queueForSend("msg2", "Message2", Normal)
    manager.queueForSend("msg3", "Message3", Critical)   # Should be queued
    manager.queueForSend("msg4", "Message4", Normal)     # Should be queued
    manager.queueForSend("msg5", "Message5", Optional)   # Should be queued
    
    await sleepAsync(chronos.milliseconds(100))
    
    ## Then
    let queueStatus = manager.getQueueStatus()
    
    check:
      queueStatus.total >= 2        # At least some messages queued
      queueStatus.critical >= 1     # Critical messages in queue
      queueStatus.normal >= 1       # Normal messages in queue
    
    await manager.stop()

suite "Generic Type Support":
  setup:
    ## Given
    let epochDuration = 60
    var sentCustomMessages: seq[TestMessage]
    
    proc testCustomSender(messageId: string, msg: TestMessage): Future[bool] {.async.} =
      sentCustomMessages.add(msg)
      await sleepAsync(chronos.milliseconds(10))
      return true

  asyncTest "custom message types - TestMessage objects":
    ## Given
    let capacity = 5
    var manager = newRateLimitManager(capacity, epochDuration, testCustomSender)
    await manager.start()
    
    ## When
    let testMsg = TestMessage(content: "Test content", id: 42)
    manager.queueForSend("custom1", testMsg, Normal)
    
    await sleepAsync(chronos.milliseconds(200))
    await manager.stop()
    
    ## Then
    check:
      sentCustomMessages.len == 1
      sentCustomMessages[0].content == "Test content"
      sentCustomMessages[0].id == 42

  asyncTest "integer message types":
    ## Given
    let capacity = 5
    var sentInts: seq[int]
    
    proc testIntSender(messageId: string, msg: int): Future[bool] {.async.} =
      sentInts.add(msg)
      await sleepAsync(chronos.milliseconds(10))
      return true
    
    var manager = newRateLimitManager(capacity, epochDuration, testIntSender)
    await manager.start()
    
    ## When
    manager.queueForSend("int1", 42, Critical)
    manager.queueForSend("int2", 100, Normal)
    manager.queueForSend("int3", 999, Optional)
    
    await sleepAsync(chronos.milliseconds(200))
    await manager.stop()
    
    ## Then
    check:
      sentInts.len == 3
      sentInts[0] == 42   # Critical sent first
      sentInts[1] == 100  # Normal sent second
      sentInts[2] == 999  # Optional sent last