# Builds and runs the tests of the portable C core on Linux.
#
#   make            unit tests
#   make e2e        end-to-end test against the real Go server
#   make clean
#
# The core is compiled with the same files as the 3DS build (../Makefile),
# minus the 3DS layer (../app).

CC      ?= cc
BUILD   := build
REPO    := $(abspath ../..)

# _DEFAULT_SOURCE exposes the POSIX functions (mkdir, opendir, mkdtemp...)
# that devkitARM's newlib provides without it.
# AddressSanitizer and UBSan when the compiler can link them (CI); without
# their runtime libraries (libasan), the tests run without them.
SANITIZE ?= $(shell echo 'int main(void){return 0;}' | \
              $(CC) -fsanitize=address,undefined -x c - -o /dev/null 2>/dev/null && \
              echo -fsanitize=address,undefined -fno-omit-frame-pointer)
# -Wno-format-truncation: messages and paths are cut on purpose by
# snprintf when they are too long for their buffer.
CFLAGS  := -std=c99 -D_DEFAULT_SOURCE -Wall -Wextra -Werror -Wno-format-truncation -g -O1 $(SANITIZE) \
           -DREPO_ROOT='"$(REPO)"'
LDFLAGS := $(SANITIZE)
CURL_CFLAGS := $(shell pkg-config --cflags libcurl)
CURL_LIBS   := $(shell pkg-config --libs libcurl)

CORE    := $(wildcard ../core/*.c)
TESTS   := main.c $(filter-out main.c e2e.c,$(wildcard *.c))

CORE_OBJ  := $(patsubst ../core/%.c,$(BUILD)/core/%.o,$(CORE))
TEST_OBJ  := $(patsubst %.c,$(BUILD)/tests/%.o,$(TESTS))
CJSON_OBJ := $(BUILD)/vendor/cJSON.o
MONO_OBJ  := $(BUILD)/vendor/monocypher.o $(BUILD)/vendor/monocypher-ed25519.o
VENDOR_OBJ := $(CJSON_OBJ) $(MONO_OBJ)

.PHONY: test e2e clean
test: $(BUILD)/run_tests
	./$(BUILD)/run_tests

# The end-to-end test links the core with the libcurl transport, not the
# fake server.
e2e: $(BUILD)/e2e
	./e2e.sh $(BUILD)/e2e

$(BUILD)/e2e: $(CORE_OBJ) $(BUILD)/tests/e2e.o $(BUILD)/tests/platform_linux.o $(VENDOR_OBJ)
	$(CC) $(LDFLAGS) -o $@ $^ $(CURL_LIBS)

$(BUILD)/run_tests: $(CORE_OBJ) $(TEST_OBJ) $(VENDOR_OBJ)
	$(CC) $(LDFLAGS) -o $@ $^ $(CURL_LIBS)

# Same stack limit as the 3DS build for the core (see ../Makefile).
$(BUILD)/core/%.o: ../core/%.c ../core/*.h
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS) -Wstack-usage=4096 $(CURL_CFLAGS) -c -o $@ $<

$(BUILD)/tests/%.o: %.c *.h ../core/*.h
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS) $(CURL_CFLAGS) -c -o $@ $<

# Third-party code: same sanitizers, without -Werror.
$(CJSON_OBJ): ../vendor/cjson/cJSON.c
	@mkdir -p $(dir $@)
	$(CC) -std=c99 -g -O1 $(SANITIZE) -c -o $@ $<

$(BUILD)/vendor/%.o: ../vendor/monocypher/%.c ../vendor/monocypher/*.h
	@mkdir -p $(dir $@)
	$(CC) -std=c99 -g -O1 $(SANITIZE) -c -o $@ $<

clean:
	rm -rf $(BUILD)
