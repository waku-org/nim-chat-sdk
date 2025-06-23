# Package

version       = "0.0.1"
author        = "Waku Chat Team"
description   = "Chat features over Waku"
license       = "MIT"
srcDir        = "src"



### Dependencies
requires "nim >= 2.2.4",
  "chronicles",
  "chronos",
  "db_connector"

task buildSharedLib, "Build shared library for C bindings":
  exec "nim c --app:lib --out:../library/c-bindings/libchatsdk.so chat_sdk/chat_sdk.nim"

task buildStaticLib, "Build static library for C bindings":
  exec "nim c --app:staticLib --out:../library/c-bindings/libchatsdk.a chat_sdk/chat_sdk.nim" 
