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

## TODO

- [ ] Follow closer the integrations from [this repo](https://github.com/logos-co/nim-c-library-guide)
- [ ] [Roadmap](https://github.com/waku-org/pm/blob/2025H2/draft-roadmap/create_chat_sdk_mvp.md)
    - [ ] [FURPS](https://github.com/waku-org/pm/blob/2025H2/FURPS/application/chat_sdk.md)