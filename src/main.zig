const help_message = @embedFile("./templates/help_message");
const std = @import("std");
const builtin = @import("builtin");
const eql = std.mem.eql;
const make_hb = @import("make");
const build = @import("build");

// rowan -> pre-alpha | amary -> alpha | flower -> beta | wood -> stable
const VERSION = "0.1.0 (rowan)";
const ZIG_VERSION = builtin.zig_version_string;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    defer {
        _ = gpa.deinit();
    }
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        display_help();
        std.process.exit(1);
    }

    if (eql(u8, args[1], "build")) {
        try build.build(allocator);
    } else if (eql(u8, args[1], "make")) {
        if (args.len < 3) {
            std.debug.print("usage: cpsb make <FILE>\n", .{});
            std.process.exit(1);
        }
        try make_hb.make(allocator, args[2]);
    } else if (eql(u8, args[1], "help")) {
        display_help();
    } else if (eql(u8, args[1], "version")) {
        std.debug.print("cpsb version {s}\n", .{VERSION});
        std.debug.print("with zig {s}\n", .{ZIG_VERSION});
    } else {
        std.debug.print("Unknown command: {s}\n", .{args[1]});
        display_help();
        std.process.exit(1);
    }

    return;
}

fn display_help() void {
    std.debug.print("{s}\n", .{help_message});
}
