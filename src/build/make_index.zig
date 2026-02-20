const std = @import("std");
const package = @import("package");
const writer = @import("writer");

pub fn make_index(allocator: std.mem.Allocator) !bool {
    var packages = std.ArrayList([]const u8){};
    defer {
        for (packages.items) |items| {
            allocator.free(items);
        }
        packages.deinit(allocator);
    }

    var dir = try std.fs.cwd().openDir(".", .{ .iterate = true });
    defer dir.close();

    var iterate = dir.iterate();
    while (try iterate.next()) |entry| {
        const ext = std.fs.path.extension(entry.name);
        if (std.mem.eql(u8, ext, ".hb")) {
            const entry_copy = try allocator.dupe(u8, entry.name);
            try packages.append(allocator, entry_copy);
        }
    }

    var packages_list = try allocator.create(package.Packages);
    defer allocator.destroy(packages_list);

    var i: usize = 0;
    for (packages.items) |pkg| {
        i += 1;
        const pkg_obj = try create_package(allocator, pkg);
        defer allocator.destroy(pkg_obj);
        packages_list.package[i] = pkg_obj.*;
    }

    try writer.packages_write(packages_list.*, "index");

    return true;
}

pub fn create_package(allocator: std.mem.Allocator, build_file: []const u8) !*package.Package {
    var pkg = try allocator.create(package.Package);

    const hb_file = try std.fs.realpathAlloc(allocator, build_file);
    defer allocator.free(hb_file);

    const name_val = try get_value(allocator, hb_file, "NAME");
    defer allocator.free(name_val);
    copy_to_fixed(&pkg.name, name_val);

    const desc_val = try get_value(allocator, hb_file, "DESC");
    defer allocator.free(desc_val);
    copy_to_fixed(&pkg.description, desc_val);

    const license_val = try get_value(allocator, hb_file, "LICENSE");
    defer allocator.free(license_val);
    copy_to_fixed(&pkg.license, license_val);

    const version_val = try get_value(allocator, hb_file, "VERSION");
    defer allocator.free(version_val);
    copy_to_fixed(&pkg.version, version_val);

    const source_val = try get_value(allocator, hb_file, "SOURCE");
    defer allocator.free(source_val);
    copy_to_fixed(&pkg.src_url, source_val);

    const depends_val = try get_value(allocator, hb_file, "DEPENDS");
    defer allocator.free(depends_val);
    try parse_depends(&pkg.depend, depends_val);

    const is_build_val = try get_value(allocator, hb_file, "IS_BUILD");
    defer allocator.free(is_build_val);
    pkg.isbuild = std.mem.eql(u8, std.mem.trim(u8, is_build_val, " \n\r\t"), "true");

    return pkg;
}

/// []const u8 を固定長配列にコピーする
fn copy_to_fixed(dest: anytype, src: []const u8) void {
    const len = @min(src.len, dest.len);
    @memcpy(dest[0..len], src[0..len]);

    // 残りをゼロで埋める
    if (len < dest.len) {
        @memset(dest[len..], 0);
    }
}

/// 依存関係をパースする
fn parse_depends(dest: *[64][32]u8, src: []const u8) !void {
    var iter = std.mem.splitSequence(u8, src, " ");
    var i: usize = 0;

    while (iter.next()) |dep| {
        if (i >= 64) break;

        const trimmed = std.mem.trim(u8, dep, " \n\r\t");
        if (trimmed.len == 0) continue;

        copy_to_fixed(&dest[i], trimmed);
        i += 1;
    }

    // 残りをゼロで初期化
    while (i < 64) : (i += 1) {
        @memset(&dest[i], 0);
    }
}

pub fn get_value(alc: std.mem.Allocator, file: []const u8, value: []const u8) ![]const u8 {
    var arena = std.heap.ArenaAllocator.init(alc);
    defer arena.deinit();

    // シェルコマンドを構築（クォートを正しく処理）
    const cmd = try std.fmt.allocPrint(
        arena.allocator(),
        ". '{s}' && echo \"${{{s}}}\"",
        .{ file, value },
    );

    var child = std.process.Child.init(
        &.{ "/usr/bin/env", "sh", "-c", cmd },
        arena.allocator(), // arena allocator を使う
    );

    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Pipe;
    child.stdin_behavior = .Ignore;

    try child.spawn();

    // stdout が null でないか確認
    if (child.stdout == null) {
        _ = try child.wait();
        return error.NoStdoutPipe;
    }

    const stdout = child.stdout.?;
    const stderr = child.stderr.?;

    // readToEndAlloc を使用
    const output = stdout.readToEndAlloc(arena.allocator(), 4096) catch |err| {
        _ = try child.wait();
        return err;
    };

    const output_err = stderr.readToEndAlloc(arena.allocator(), 4096) catch |err| {
        _ = try child.wait();
        return err;
    };

    // プロセスの終了を待つ
    const result = try child.wait();

    if (result != .Exited or result.Exited != 0) {
        std.debug.print("Command failed: {s} for {s}\n", .{ cmd, value });
        std.debug.print("Exit code: {d}\n", .{result.Exited});
        std.debug.print("stdout: {s}\n", .{output});
        std.debug.print("stderr: {s}\n", .{output_err});
        return error.CommandExecError;
    }

    // 末尾の空白や改行を削除したものを alc で確保してコピー
    const trimmed = std.mem.trim(u8, output, " \n\r\t");
    return try alc.dupe(u8, trimmed);
}
