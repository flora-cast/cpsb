const build_script = @embedFile("./scripts/build.sh");
const std = @import("std");
const make_index = @import("make_index");
const package = @import("package");
const fetch = @import("fetch");
const zstig = @import("zstig");
const tar_creation = @import("./tar_creation.zig");
const tar = std.tar;

pub fn make(allocator: std.mem.Allocator, file: []const u8) !void {
    const package_info = try make_index.create_package(allocator, file);
    defer allocator.destroy(package_info);

    if (try check_linux_distribution(allocator) == .alpine) {
        install_dependencies(allocator, &package_info.depend) catch |err| switch (err) {
            error.InstallFailed => std.log.err("Failed to install packages", .{}),
            else => {
                std.debug.print("Unknown Error: {any}\n", .{err});
                std.process.exit(33);
            },
        };
    }

    if (!exists("/etc/cpsb/build.sh")) {
        _ = try makeDirAbsoluteRecursive(allocator, "/etc/cpsb/");
        var file_sh = try std.fs.createFileAbsolute("/etc/cpsb/build.sh", .{});
        defer file_sh.close();

        try file_sh.writeAll(build_script);
    }

    const b3_file = try std.fmt.allocPrint(allocator, "{s}.b3", .{file});
    defer allocator.free(b3_file);

    build_package(allocator, file, package_info.*) catch |err| {
        std.debug.print("\nFailed to build package: {any}\n", .{err});
        std.process.exit(1);
    };

    packaging(allocator, file, package_info.*) catch |err| {
        std.debug.print("\nFailed to packaging package: {any}\n", .{err});
        std.process.exit(1);
    };
}

fn install_dependencies(allocator: std.mem.Allocator, packages: *const [64][32]u8) !void {
    var packages_slice: [64][]const u8 = undefined;
    var count: usize = 0;

    for (packages) |pkg| {
        const name = std.mem.trim(u8, &pkg, " \n\r\t\x00");

        if (name.len == 0) continue;

        packages_slice[count] = name;
        count += 1;
    }

    const packages_joined = try std.mem.join(allocator, " ", packages_slice[0..count]);
    defer allocator.free(packages_joined);

    std.debug.print("Installing dependencies...\n", .{});

    var child = std.process.Child.init(&.{
        "/usr/sbin/apk",
        "add",
        "--no-cache",
        packages_joined,
    }, allocator);

    child.stdout_behavior = .Inherit;
    child.stderr_behavior = .Inherit;
    child.stdin_behavior = .Inherit;

    const result = try child.spawnAndWait();

    if (result != .Exited or result.Exited != 0) {
        std.debug.print("Failed to install packages\n", .{});
        return error.InstallFailed;
    }
}

fn build_package(allocator: std.mem.Allocator, hb_file: []const u8, package_info: package.Package) !void {
    std.debug.print("fetch: {s}", .{package_info.src_url});

    const name = std.mem.sliceTo(&package_info.name, 0);
    const version = std.mem.sliceTo(&package_info.version, 0);

    const source_dir = "/var/lib/cpsb/build/";

    const source_file = try std.fmt.allocPrint(allocator, "{s}/src-{s}-{s}", .{ source_dir, name, version });
    defer allocator.free(source_file);

    _ = try makeDirAbsoluteRecursive(allocator, source_dir);
    try fetch_source(allocator, &package_info.src_url, source_file);
    // defer deleteTreeAbsolute(source_file);

    std.debug.print("\r\x1b[2Kbuilding: {s}\n", .{package_info.name});

    const package_dir = try std.fmt.allocPrint(allocator, "/var/lib/cpsb/build/packaging-{s}", .{name});
    defer allocator.free(package_dir);

    const build_dir = try std.fmt.allocPrint(allocator, "/var/lib/cpsb/build/build-{s}", .{name});
    defer allocator.free(build_dir);

    const build_file = try std.fs.realpathAlloc(allocator, hb_file);
    defer allocator.free(build_file);

    const temp_dir = try std.fmt.allocPrint(allocator, "/var/lib/cpsb/build/temp-{s}", .{name});
    defer allocator.free(temp_dir);

    _ = try makeDirAbsoluteRecursive(allocator, package_dir);
    _ = try makeDirAbsoluteRecursive(allocator, build_dir);
    _ = try makeDirAbsoluteRecursive(allocator, temp_dir);

    var env_map = try std.process.getEnvMap(allocator);
    defer env_map.deinit();

    try env_map.put("PACKAGE_DIR", package_dir);
    try env_map.put("SOURCE_FILE", source_file);
    try env_map.put("BUILD_DIR", build_dir);
    try env_map.put("BUILD_FILE", build_file);

    var child = std.process.Child.init(&.{
        "/usr/bin/env",
        "sh",
        "-c",
        ". /etc/cpsb/build.sh; build_package",
    }, allocator);

    child.env_map = &env_map;
    child.stdout_behavior = .Inherit;
    child.stderr_behavior = .Inherit;
    child.stdin_behavior = .Inherit;

    const result = try child.spawnAndWait();

    if (result != .Exited or result.Exited != 0) {
        std.log.err("Failed to build package", .{});
        return error.BuildFailed;
    }

    std.debug.print("build(): done\n", .{});
}

fn packaging(allocator: std.mem.Allocator, file: []const u8, package_info: package.Package) !void {
    const name = std.mem.sliceTo(&package_info.name, 0);
    const version = std.mem.sliceTo(&package_info.version, 0);

    const source_dir = "/var/lib/cpsb/build/";

    const source_file = try std.fmt.allocPrint(allocator, "{s}/src-{s}-{s}", .{ source_dir, name, version });
    defer allocator.free(source_file);

    const package_dir = try std.fmt.allocPrint(allocator, "/var/lib/cpsb/build/packaging-{s}/", .{name});
    defer allocator.free(package_dir);

    const build_dir = try std.fmt.allocPrint(allocator, "/var/lib/cpsb/build/build-{s}", .{name});
    defer allocator.free(build_dir);

    const temp_dir = try std.fmt.allocPrint(allocator, "/var/lib/cpsb/build/temp-{s}", .{name});
    defer allocator.free(temp_dir);

    const build_file = try std.fs.realpathAlloc(allocator, file);
    defer allocator.free(build_file);

    var env_map = try std.process.getEnvMap(allocator);
    defer env_map.deinit();

    try env_map.put("PACKAGE_DIR", package_dir);
    try env_map.put("SOURCE_FILE", source_file);
    try env_map.put("BUILD_DIR", build_dir);
    try env_map.put("BUILD_FILE", build_file);
    std.debug.print("\r\x1b[2Kpackage(): {s}", .{package_info.name});

    {
        var child = std.process.Child.init(&.{
            "/usr/bin/env",
            "sh",
            "-c",
            ". /etc/cpsb/build.sh; packaging_package",
        }, allocator);

        child.env_map = &env_map;
        child.stdout_behavior = .Inherit;
        child.stderr_behavior = .Inherit;
        child.stdin_behavior = .Inherit;

        const result = try child.spawnAndWait();

        if (result != .Exited or result.Exited != 0) {
            std.log.err("Failed to packaging package\n", .{});
            return error.BuildFailed;
        }
    }

    std.debug.print("\r\x1b[2Kcompressing: {s}", .{name});
    const output = try std.fmt.allocPrint(allocator, "{s}.clos", .{name});
    defer allocator.free(output);
    _ = try std.fs.cwd().createFile(output, .{});

    const realpath = try std.fs.realpathAlloc(allocator, output);
    defer allocator.free(realpath);

    const temp_tar_file = try std.fmt.allocPrint(allocator, "{s}/{s}.tar", .{ temp_dir, name });
    defer allocator.free(temp_tar_file);

    // temp tar file
    std.debug.print("\r\x1b[2Kcompressing: {s}\tcollect files", .{name});
    try tar_creation.createTar(allocator, package_dir, temp_tar_file);

    {
        std.debug.print("\r\x1b[2Kcompressing: {s}\tcompressing to zstd", .{name});

        const input_file = try std.fs.openFileAbsolute(temp_tar_file, .{});
        defer input_file.close();

        const output_file = try std.fs.openFileAbsolute(realpath, .{ .mode = .read_write });
        defer output_file.close();

        const content = try input_file.readToEndAlloc(allocator, std.math.maxInt(usize));
        defer allocator.free(content);

        const out = try zstig.compress(content, allocator);
        defer allocator.free(out);

        try output_file.writeAll(out);
    }

    std.debug.print("\r\x1b[2Kcompress: done\n", .{});
    std.debug.print("package created to: {s}\n", .{realpath});

    // Clean up directories after tar creation is complete
    deleteTreeAbsolute(source_file);
    deleteTreeAbsolute(package_dir);
    deleteTreeAbsolute(build_dir);
    deleteTreeAbsolute(temp_dir);
}

fn fetch_source(alc: std.mem.Allocator, url: []const u8, save_file: []const u8) !void {
    const url_z = try alc.dupeZ(u8, url);
    defer alc.free(url_z);

    const save_file_path = std.mem.sliceTo(save_file, 0);
    var file = try std.fs.createFileAbsolute(save_file_path, .{});
    defer file.close();

    try fetch.fetch_file(url_z, &file);
}

pub fn makeDirAbsoluteRecursive(allocator: std.mem.Allocator, dir_path: []const u8) !void {
    var current_path = std.ArrayList(u8){};
    defer current_path.deinit(allocator);

    if (dir_path.len > 0 and dir_path[0] == '/') {
        try current_path.append(allocator, '/');
    }

    var parts = std.mem.splitSequence(u8, dir_path, "/");
    while (parts.next()) |part| {
        if (part.len == 0) continue;

        if (current_path.items.len > 1) {
            try current_path.append(allocator, '/');
        }
        try current_path.appendSlice(allocator, part);

        std.fs.makeDirAbsolute(current_path.items) catch |err| {
            if (err != error.PathAlreadyExists) {
                return err;
            }
        };
    }
}

fn exists(path: []const u8) bool {
    std.fs.cwd().access(path, .{}) catch return false;
    return true;
}

fn deleteTreeAbsolute(file: []const u8) void {
    std.fs.deleteTreeAbsolute(file) catch |err| {
        std.log.err("Failed to delete directory: {any}\n", .{err});
    };
}

const Distribution = enum {
    alpine,
    shary,
    other,
};

fn check_linux_distribution(allocator: std.mem.Allocator) !Distribution {
    const os_releases = try std.fs.openFileAbsolute("/etc/os-release", .{ .mode = .read_only });

    const readed = try os_releases.readToEndAlloc(allocator, std.math.maxInt(u32));
    defer allocator.free(readed);

    std.debug.print("os-release: {s}\n", .{readed});

    var split = std.mem.splitAny(u8, readed, "=\n");

    var id: []const u8 = &.{};
    var wait_id = false;

    while (split.next()) |entry| {
        std.debug.print("entry: {s}\n", .{entry});
        if (std.mem.eql(u8, entry, "ID")) {
            wait_id = true;
            continue;
        }

        if (wait_id) {
            id = entry;
            break;
        }
    }

    if (std.mem.eql(u8, id, "alpine")) {
        return .alpine;
    } else if (std.mem.eql(u8, id, "shary")) {
        return .shary;
    } else {
        return .other;
    }
}
