# ChatSDK Makefile
# This builds the complete chain: Nim -> C bindings -> Go bindings -> Go example

.PHONY: all clean build-nim build-c build-go run-go-example help

# Default target
all: build-nim build-c build-go

# Help target
help:
	@echo "ChatSDK Build System"
	@echo "===================="
	@echo "Available targets:"
	@echo "  all              - Build everything (Nim + C + Go)"
	@echo "  build-nim        - Build Nim library"
	@echo "  build-c          - Build C bindings (shared library)"
	@echo "  build-go         - Build Go bindings"
	@echo "  run-go-example   - Run the Go example application"
	@echo "  clean            - Clean all build artifacts"
	@echo "  help             - Show this help message"

# Build Nim library
build-nim: libchatsdk

libchatsdk:
	@echo "Building Nim library..."
	cd chat_sdk && nim c --app:lib --opt:speed --mm:refc --out:../library/c-bindings/libchatsdk.so chat_sdk.nim

# Build C bindings
build-c: libchatsdk
	@echo "C bindings ready (built with Nim)"

# Build Go bindings (just verify they compile)
build-go: build-c
	@echo "Building Go bindings..."
	cd library/go-bindings && go build .

# Run Go example
run-go-example: build-go
	@echo "Running Go example..."
	cd examples/go-app && \
	LD_LIBRARY_PATH=../../library/c-bindings:$$LD_LIBRARY_PATH \
	go run main.go

# Clean all build artifacts
clean:
	@echo "Cleaning build artifacts..."
	rm -f library/c-bindings/*.so library/c-bindings/*.a
	rm -rf chat_sdk/nimcache library/c-bindings/nimcache
	cd library/go-bindings && go clean
	cd examples/go-app && go clean

# Test the Nim library directly
test-nim:
	@echo "Testing Nim library directly..."
	cd chat_sdk && nim r chat_sdk.nim 