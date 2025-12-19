//! Combining Class Data

s1: []u16 = undefined,
s2: []u8 = undefined,

const CombiningData = @This();

pub fn init(allocator: mem.Allocator) !CombiningData {
    const in_bytes = @embedFile("ccc");
    var input: Io.Reader = .fixed(in_bytes);
    var decomp_buffer: [compress.flate.max_window_len]u8 = undefined;
    var decompress: compress.flate.Decompress = .init(&input, .raw, &decomp_buffer);
    const reader = &decompress.reader;

    const endian = builtin.cpu.arch.endian();

    var cbdata = CombiningData{};

    const stage_1_len: u16 = try reader.takeInt(u16, endian);
    cbdata.s1 = try allocator.alloc(u16, stage_1_len);
    errdefer allocator.free(cbdata.s1);
    for (0..stage_1_len) |i| cbdata.s1[i] = try reader.takeInt(u16, endian);

    const stage_2_len: u16 = try reader.takeInt(u16, endian);
    cbdata.s2 = try allocator.alloc(u8, stage_2_len);
    errdefer allocator.free(cbdata.s2);
    try reader.readSliceAll(cbdata.s2);

    return cbdata;
}

pub fn deinit(cbdata: *const CombiningData, allocator: mem.Allocator) void {
    allocator.free(cbdata.s1);
    allocator.free(cbdata.s2);
}

/// Returns the canonical combining class for a code point.
pub fn ccc(cbdata: CombiningData, cp: u21) u8 {
    return cbdata.s2[cbdata.s1[cp >> 8] + (cp & 0xff)];
}

/// True if `cp` is a starter code point, not a combining character.
pub fn isStarter(cbdata: CombiningData, cp: u21) bool {
    return cbdata.s2[cbdata.s1[cp >> 8] + (cp & 0xff)] == 0;
}

const std = @import("std");
const builtin = @import("builtin");
const compress = std.compress;
const Io = std.Io;
const mem = std.mem;
