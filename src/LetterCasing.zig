const CodePointIterator = @import("code_point").Iterator;

case_map: [][2]u21 = undefined,
prop_s1: []u16 = undefined,
prop_s2: []u8 = undefined,

const LetterCasing = @This();

pub fn init(allocator: Allocator) Allocator.Error!LetterCasing {
    var case = LetterCasing{};
    try case.setup(allocator);
    return case;
}

pub fn setup(case: *LetterCasing, allocator: Allocator) Allocator.Error!void {
    case.setupInner(allocator) catch |err| {
        switch (err) {
            error.OutOfMemory => |e| return e,
            else => unreachable,
        }
    };
}

inline fn setupInner(self: *LetterCasing, allocator: mem.Allocator) !void {
    const endian = builtin.cpu.arch.endian();

    self.case_map = try allocator.alloc([2]u21, 0x110000);
    errdefer allocator.free(self.case_map);

    for (0..0x110000) |i| {
        const cp: u21 = @intCast(i);
        self.case_map[cp] = .{ cp, cp };
    }

    var decomp_buffer: [compress.flate.max_window_len]u8 = undefined;

    // Uppercase
    const upper_bytes = @embedFile("upper");
    var upper_input: std.Io.Reader = .fixed(upper_bytes);
    var upper_decomp = compress.flate.Decompress.init(&upper_input, .raw, &decomp_buffer);

    while (true) {
        const cp = try upper_decomp.reader.takeInt(i24, endian);
        if (cp == 0) break;
        const diff = try upper_decomp.reader.takeInt(i24, endian);
        self.case_map[@intCast(cp)][0] = @intCast(cp + diff);
    }

    // Lowercase
    const lower_bytes = @embedFile("lower");
    var lower_input: std.Io.Reader = .fixed(lower_bytes);
    var lower_decomp = compress.flate.Decompress.init(&lower_input, .raw, &decomp_buffer);

    while (true) {
        const cp = try lower_decomp.reader.takeInt(i24, endian);
        if (cp == 0) break;
        const diff = try lower_decomp.reader.takeInt(i24, endian);
        self.case_map[@intCast(cp)][1] = @intCast(cp + diff);
    }

    // Case properties
    const cp_bytes = @embedFile("case_prop");
    var cp_input: std.Io.Reader = .fixed(cp_bytes);
    var cp_decomp = compress.flate.Decompress.init(&cp_input, .raw, &decomp_buffer);

    const stage_1_len: u16 = try cp_decomp.reader.takeInt(u16, endian);
    self.prop_s1 = try allocator.alloc(u16, stage_1_len);
    errdefer allocator.free(self.prop_s1);
    for (0..stage_1_len) |i| self.prop_s1[i] = try cp_decomp.reader.takeInt(u16, endian);

    const stage_2_len: u16 = try cp_decomp.reader.takeInt(u16, endian);
    self.prop_s2 = try allocator.alloc(u8, stage_2_len);
    errdefer allocator.free(self.prop_s2);
    try cp_decomp.reader.readSliceAll(self.prop_s2);
}

pub fn deinit(self: *const LetterCasing, allocator: mem.Allocator) void {
    allocator.free(self.case_map);
    allocator.free(self.prop_s1);
    allocator.free(self.prop_s2);
}

// Returns true if `cp` is either upper, lower, or title case.
pub fn isCased(self: LetterCasing, cp: u21) bool {
    return self.prop_s2[self.prop_s1[cp >> 8] + (cp & 0xff)] & 4 == 4;
}

// Returns true if `cp` is uppercase.
pub fn isUpper(self: LetterCasing, cp: u21) bool {
    return self.prop_s2[self.prop_s1[cp >> 8] + (cp & 0xff)] & 2 == 2;
}

/// Returns true if `str` is all uppercase.
pub fn isUpperStr(self: LetterCasing, str: []const u8) bool {
    var iter = CodePointIterator{ .bytes = str };

    return while (iter.next()) |cp| {
        if (self.isCased(cp.code) and !self.isUpper(cp.code)) break false;
    } else true;
}

test "isUpperStr" {
    const cd = try init(testing.allocator);
    defer cd.deinit(testing.allocator);

    try testing.expect(cd.isUpperStr("HELLO, WORLD 2112!"));
    try testing.expect(!cd.isUpperStr("hello, world 2112!"));
    try testing.expect(!cd.isUpperStr("Hello, World 2112!"));
}

/// Returns uppercase mapping for `cp`.
pub fn toUpper(self: LetterCasing, cp: u21) u21 {
    return self.case_map[cp][0];
}

/// Returns a new string with all letters in uppercase.
/// Caller must free returned bytes with `allocator`.
pub fn toUpperStr(
    self: LetterCasing,
    allocator: mem.Allocator,
    str: []const u8,
) ![]u8 {
    var bytes: std.ArrayList(u8) = .empty;
    defer bytes.deinit(allocator);

    var iter = CodePointIterator{ .bytes = str };
    var buf: [4]u8 = undefined;

    while (iter.next()) |cp| {
        const len = try unicode.utf8Encode(self.toUpper(cp.code), &buf);
        try bytes.appendSlice(allocator, buf[0..len]);
    }

    return try bytes.toOwnedSlice(allocator);
}

test "toUpperStr" {
    const cd = try init(testing.allocator);
    defer cd.deinit(testing.allocator);

    const uppered = try cd.toUpperStr(testing.allocator, "Hello, World 2112!");
    defer testing.allocator.free(uppered);
    try testing.expectEqualStrings("HELLO, WORLD 2112!", uppered);
}

// Returns true if `cp` is lowercase.
pub fn isLower(self: LetterCasing, cp: u21) bool {
    return self.prop_s2[self.prop_s1[cp >> 8] + (cp & 0xff)] & 1 == 1;
}

/// Returns true if `str` is all lowercase.
pub fn isLowerStr(self: LetterCasing, str: []const u8) bool {
    var iter = CodePointIterator{ .bytes = str };

    return while (iter.next()) |cp| {
        if (self.isCased(cp.code) and !self.isLower(cp.code)) break false;
    } else true;
}

test "isLowerStr" {
    const cd = try init(testing.allocator);
    defer cd.deinit(testing.allocator);

    try testing.expect(cd.isLowerStr("hello, world 2112!"));
    try testing.expect(!cd.isLowerStr("HELLO, WORLD 2112!"));
    try testing.expect(!cd.isLowerStr("Hello, World 2112!"));
}

/// Returns lowercase mapping for `cp`.
pub fn toLower(self: LetterCasing, cp: u21) u21 {
    return self.case_map[cp][1];
}

/// Returns a new string with all letters in lowercase.
/// Caller must free returned bytes with `allocator`.
pub fn toLowerStr(
    self: LetterCasing,
    allocator: mem.Allocator,
    str: []const u8,
) ![]u8 {
    var bytes: std.ArrayList(u8) = .empty;
    defer bytes.deinit(allocator);

    var iter = CodePointIterator{ .bytes = str };
    var buf: [4]u8 = undefined;

    while (iter.next()) |cp| {
        const len = try unicode.utf8Encode(self.toLower(cp.code), &buf);
        try bytes.appendSlice(allocator, buf[0..len]);
    }

    return try bytes.toOwnedSlice(allocator);
}

test "toLowerStr" {
    const cd = try init(testing.allocator);
    defer cd.deinit(testing.allocator);

    const lowered = try cd.toLowerStr(testing.allocator, "Hello, World 2112!");
    defer testing.allocator.free(lowered);
    try testing.expectEqualStrings("hello, world 2112!", lowered);
}

fn testAllocator(allocator: Allocator) !void {
    var prop = try LetterCasing.init(allocator);
    prop.deinit(allocator);
}

test "Allocation failure" {
    try testing.checkAllAllocationFailures(testing.allocator, testAllocator, .{});
}

const std = @import("std");
const builtin = @import("builtin");
const compress = std.compress;
const mem = std.mem;
const Allocator = std.mem.Allocator;
const testing = std.testing;
const unicode = std.unicode;
