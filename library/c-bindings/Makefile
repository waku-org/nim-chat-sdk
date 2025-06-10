CC = gcc
CFLAGS = -Wall -Wextra -fPIC
NIMFLAGS = --app:lib 

# Directories
SRC_DIR = ../../src
BUILD_DIR = .

# Targets
SHARED_LIB = libchatsdk.so
STATIC_LIB = libchatsdk.a
HEADER = chatsdk.h

.PHONY: all clean shared static

all: shared static

shared: $(SHARED_LIB)

static: $(STATIC_LIB)

$(SHARED_LIB): $(SRC_DIR)/chat_sdk.nim $(HEADER)
	cd $(SRC_DIR) && nim c $(NIMFLAGS) --out:../library/c-bindings/$(SHARED_LIB) chat_sdk.nim

$(STATIC_LIB): $(SRC_DIR)/chat_sdk.nim $(HEADER)
	cd $(SRC_DIR) && nim c $(NIMFLAGS) --app:staticLib --out:../library/c-bindings/$(STATIC_LIB) chat_sdk.nim

clean:
	rm -f $(SHARED_LIB) $(STATIC_LIB) *.o *.so *.a
	rm -rf nimcache

install: $(SHARED_LIB) $(HEADER)
	sudo cp $(SHARED_LIB) /usr/local/lib/
	sudo cp $(HEADER) /usr/local/include/
	sudo ldconfig 