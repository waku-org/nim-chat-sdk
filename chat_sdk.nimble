# Package

version       = "0.0.1"
author        = "Waku Chat Team"
description   = "Chat features over Waku"
license       = "MIT"
srcDir        = "src"


# Dependencies

requires "nim >= 2.0.0"
requires "leopard >= 0.1.0 & < 0.2.0"
requires "nimcrypto >= 0.6.3"
requires "results"
requires "chronicles"


task demo, "Run demo":
  exec "nim c -r src/chat_sdk/segmentation.nim"