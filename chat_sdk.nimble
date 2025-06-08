# Package

version       = "0.0.1"
author        = "Waku Chat Team"
description   = "Chat features over Waku"
license       = "MIT"
srcDir        = "src"


# Dependencies

requires "nim >= 2.0.0"

task buildSharedLib, "Build shared library for C bindings":
  exec "nim c --app:lib --out:../bindings/c-bindings/libchatsdk.so src/chat_sdk.nim"

task buildStaticLib, "Build static library for C bindings":
  exec "nim c --app:staticLib --out:../bindings/c-bindings/libchatsdk.a src/chat_sdk.nim" 
