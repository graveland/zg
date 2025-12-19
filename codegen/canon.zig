const std = @import("std");
const builtin = @import("builtin");

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Process UnicodeData.txt
    const in_data = try std.fs.cwd().readFileAlloc("data/unicode/UnicodeData.txt", allocator, .unlimited);
    var in_lines = std.mem.splitScalar(u8, in_data, '\n');

    var args_iter = try std.process.argsWithAllocator(allocator);
    defer args_iter.deinit();
    _ = args_iter.skip();
    const output_path = args_iter.next() orelse @panic("No output file arg!");

    const flate = std.compress.flate;
    var out_file = try std.fs.cwd().createFile(output_path, .{});
    defer out_file.close();

    var file_buf: [4096]u8 = undefined;
    var file_writer = out_file.writer(&file_buf);

    var deflate_buf: [flate.max_window_len]u8 = undefined;
    var compress = try flate.Compress.init(&file_writer.interface, &deflate_buf, .raw, .best);

    const endian = builtin.cpu.arch.endian();

    lines: while (in_lines.next()) |line| {
        if (line.len == 0) continue;

        var field_iter = std.mem.splitScalar(u8, line, ';');
        var cps: [3]u24 = undefined;
        var len: u8 = 2;

        var i: usize = 0;
        while (field_iter.next()) |field| : (i += 1) {
            switch (i) {
                0 => cps[0] = try std.fmt.parseInt(u24, field, 16),

                5 => {
                    // Not canonical.
                    if (field.len == 0 or field[0] == '<') continue :lines;
                    if (std.mem.indexOfScalar(u8, field, ' ')) |space| {
                        // Canonical
                        len = 3;
                        cps[1] = try std.fmt.parseInt(u24, field[0..space], 16);
                        cps[2] = try std.fmt.parseInt(u24, field[space + 1 ..], 16);
                    } else {
                        // Singleton
                        cps[1] = try std.fmt.parseInt(u24, field, 16);
                    }
                },

                2 => if (line[0] == '<') continue :lines,

                else => {},
            }
        }

        try compress.writer.writeInt(u8, @intCast(len), endian);
        for (cps[0..len]) |cp| try compress.writer.writeInt(u24, cp, endian);
    }

    try compress.writer.writeInt(u16, 0, endian);
    try compress.writer.flush();
    try file_writer.interface.flush();
}
