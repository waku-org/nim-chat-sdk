# This is just an example to get you started. You may wish to put all of your
# tests into a single file, or separate them into multiple `test1`, `test2`
# etc. files (better names are recommended, just make sure the name starts with
# the letter 't').
#
# To run these tests, simply execute `nimble test`.

import unittest, sequtils, random
import results
import chat_sdk/segmentation  # Replace with the actual file name

test "can add":
  check add2(5, 5) == 10

suite "Message Segmentation":
  let testPayload = toSeq(0..999).mapIt(byte(it))
  let testMessage = WakuNewMessage(payload: testPayload)
  let sender = MessageSender(
    messaging: Messaging(maxMessageSize: 500),
    persistence: initPersistence()
  )

  test "Segment and reassemble full segments":
    let segmentResult = sender.segmentMessage(testMessage)
    check segmentResult.isOk
    var segments = segmentResult.get()
    check segments.len > 0

    # Shuffle segment order for out-of-order test
    segments.shuffle()

    for segment in segments:
      var statusMsg: StatusMessage
      statusMsg.transportLayer = TransportLayer(
        hash: @[byte 0, 1, 2],  # Dummy hash
        payload: segment.payload,
        sigPubKey: @[byte 3, 4, 5]
      )
      let result = sender.handleSegmentationLayerV2(statusMsg)
      discard result  # Ignore intermediate errors

    # One last run to trigger completion
    var finalStatus: StatusMessage
    finalStatus.transportLayer = TransportLayer(
      hash: @[byte 0, 1, 2],
      payload: segments[0].payload,
      sigPubKey: @[byte 3, 4, 5]
    )
    let finalResult = sender.handleSegmentationLayerV2(finalStatus)
    check finalResult.isOk

    # Check payload restored
    check finalStatus.transportLayer.payload == testPayload[0..<finalStatus.transportLayer.payload.len]