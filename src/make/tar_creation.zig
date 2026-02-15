const std = @import("std");
const microtar = @import("microtar_zig");

pub fn createTar(allocator: std.mem.Allocator, source_dir: []const u8, output_file: []const u8) !void {
    const output_file_c = try allocator.dupeZ(u8, output_file);
    defer allocator.free(output_file_c);

    var tar = try microtar.MicroTar.init(output_file_c, "w");
    defer tar.deinit();

    var source_dir_opened = try std.fs.cwd().openDir(source_dir, .{ .iterate = true });
    defer source_dir_opened.close();

    try addFileRecursive(allocator, &tar, &source_dir_opened, source_dir, "");
    try tar.finalize();
}

fn addFileRecursive(allocator: std.mem.Allocator, tar: *microtar.MicroTar, dir: *std.fs.Dir, base_path: []const u8, current_path: []const u8) !void {
    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        const full_path = if (current_path.len == 0)
            try allocator.dupe(u8, entry.name)
        else
            try std.fmt.allocPrint(allocator, "{s}/{s}", .{ current_path, entry.name });
        defer allocator.free(full_path);

        const disk_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ base_path, full_path });
        defer allocator.free(disk_path);

        if (entry.kind == .file) {
            const tar_path_c = try allocator.dupeZ(u8, full_path);
            defer allocator.free(tar_path_c);

            try tar.addFileFromDisk(disk_path, tar_path_c);
        } else if (entry.kind == .directory) {
            var subdir = try dir.openDir(entry.name, .{ .iterate = true });
            defer subdir.close();
            try addFileRecursive(allocator, tar, &subdir, base_path, full_path);
        }
    }
}
