# Chat SDK

## Quick Start

### Build Everything
```bash
# Build the complete chain: Nim → C → Go
make all

# Or step by step:
make build-nim    # Build Nim library to shared library
make build-c      # Prepare C bindings
make build-go     # Verify Go bindings compile
```

### Run the Go Example
```bash
make run-go-example
```