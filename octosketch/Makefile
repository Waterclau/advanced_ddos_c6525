# OctoSketch DPDK Detector Makefile

APP = octosketch_detector

SRCS = detector.c
OBJS = $(SRCS:.c=.o)

# Pkg-config
PKGCONF ?= pkg-config
PC_FILE := $(shell $(PKGCONF) --path libdpdk 2>/dev/null)

# Compiler flags
CFLAGS += -O3 -march=native -g -Wall -Wextra
CFLAGS += $(shell $(PKGCONF) --cflags libdpdk)
CFLAGS += -I.

# Linker flags
LDFLAGS += $(shell $(PKGCONF) --libs libdpdk)
LDFLAGS += -lpthread -lm -lnuma

# Targets
.PHONY: all clean

all: $(APP)

$(APP): $(OBJS)
	@echo "[LD] $@"
	@$(CC) $(OBJS) -o $@ $(LDFLAGS)

%.o: %.c attacks.h
	@echo "[CC] $<"
	@$(CC) $(CFLAGS) -c $< -o $@

clean:
	@echo "[CLEAN]"
	@rm -f $(APP) $(OBJS)

info:
	@echo "DPDK version: $(shell $(PKGCONF) --modversion libdpdk)"
	@echo "CFLAGS: $(CFLAGS)"
	@echo "LDFLAGS: $(LDFLAGS)"
