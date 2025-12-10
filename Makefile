ZIG = zig
PREFIX ?=/usr

.PHONY: all install fmt


all:
	zig build -Doptimize=ReleaseFast

distclean: clean

clean:
	rm -rf ./external/minisign/zig-out 
	rm -rf ./external/minisign/.zig-cache
	rm -rf ./src/external-bin
	rm -rf ./zig-out
	rm -rf ./.zig-cache

install:
	install -Dm755 ./zig-out/bin/cpsb "$(PREFIX)/bin/cpsb"

fmt:
	find src -type f -name '*.zig' -exec zig fmt {} +
