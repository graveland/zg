const dbg_print = false;

test "Unicode normalization tests" {
    var arena = heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const n = try Normalize.init(allocator);
    defer n.deinit(allocator);

    const file = try fs.cwd().openFile("data/unicode/NormalizationTest.txt", .{});
    defer file.close();

    const content = try readFileContents(allocator, file);
    defer allocator.free(content);

    var cp_buf: [4]u8 = undefined;
    var line_iter = LineIterator.init(content);

    while (line_iter.next()) |line| {
        // Iterate over fields.
        var fields = mem.splitScalar(u8, line, ';');
        var field_index: usize = 0;
        var input: []u8 = undefined;
        defer allocator.free(input);

        while (fields.next()) |field| : (field_index += 1) {
            if (field_index == 0) {
                var i_buf: std.ArrayList(u8) = .empty;
                defer i_buf.deinit(allocator);

                var i_fields = mem.splitScalar(u8, field, ' ');
                while (i_fields.next()) |s| {
                    const icp = try fmt.parseInt(u21, s, 16);
                    const len = try unicode.utf8Encode(icp, &cp_buf);
                    try i_buf.appendSlice(allocator, cp_buf[0..len]);
                }

                input = try i_buf.toOwnedSlice(allocator);
            } else if (field_index == 1) {
                if (dbg_print) debug.print("\n*** {s} ***\n", .{line});
                // NFC, time to test.
                var w_buf: std.ArrayList(u8) = .empty;
                defer w_buf.deinit(allocator);

                var w_fields = mem.splitScalar(u8, field, ' ');
                while (w_fields.next()) |s| {
                    const wcp = try fmt.parseInt(u21, s, 16);
                    const len = try unicode.utf8Encode(wcp, &cp_buf);
                    try w_buf.appendSlice(allocator, cp_buf[0..len]);
                }

                const want = w_buf.items;
                var got = try n.nfc(allocator, input);
                defer got.deinit(allocator);

                try testing.expectEqualStrings(want, got.slice);
            } else if (field_index == 2) {
                // NFD, time to test.
                var w_buf: std.ArrayList(u8) = .empty;
                defer w_buf.deinit(allocator);

                var w_fields = mem.splitScalar(u8, field, ' ');
                while (w_fields.next()) |s| {
                    const wcp = try fmt.parseInt(u21, s, 16);
                    const len = try unicode.utf8Encode(wcp, &cp_buf);
                    try w_buf.appendSlice(allocator, cp_buf[0..len]);
                }

                const want = w_buf.items;
                var got = try n.nfd(allocator, input);
                defer got.deinit(allocator);

                try testing.expectEqualStrings(want, got.slice);
            } else if (field_index == 3) {
                // NFKC, time to test.
                var w_buf: std.ArrayList(u8) = .empty;
                defer w_buf.deinit(allocator);

                var w_fields = mem.splitScalar(u8, field, ' ');
                while (w_fields.next()) |s| {
                    const wcp = try fmt.parseInt(u21, s, 16);
                    const len = try unicode.utf8Encode(wcp, &cp_buf);
                    try w_buf.appendSlice(allocator, cp_buf[0..len]);
                }

                const want = w_buf.items;
                var got = try n.nfkc(allocator, input);
                defer got.deinit(allocator);

                try testing.expectEqualStrings(want, got.slice);
            } else if (field_index == 4) {
                // NFKD, time to test.
                var w_buf: std.ArrayList(u8) = .empty;
                defer w_buf.deinit(allocator);

                var w_fields = mem.splitScalar(u8, field, ' ');
                while (w_fields.next()) |s| {
                    const wcp = try fmt.parseInt(u21, s, 16);
                    const len = try unicode.utf8Encode(wcp, &cp_buf);
                    try w_buf.appendSlice(allocator, cp_buf[0..len]);
                }

                const want = w_buf.items;
                const got = try n.nfkd(allocator, input);
                defer got.deinit(allocator);

                try testing.expectEqualStrings(want, got.slice);
            } else {
                continue;
            }
        }
    }
}

test "Segmentation GraphemeIterator" {
    const allocator = std.testing.allocator;
    const file = try std.fs.cwd().openFile("data/unicode/auxiliary/GraphemeBreakTest.txt", .{});
    defer file.close();

    const content = try readFileContents(allocator, file);
    defer allocator.free(content);

    const graph = try Graphemes.init(allocator);
    defer graph.deinit(allocator);

    var line_iter = LineIterator.init(content);

    while (line_iter.next()) |raw| {
        // Clean up.
        var line = std.mem.trimStart(u8, raw, "÷ ");
        if (std.mem.indexOf(u8, line, " ÷\t")) |final| {
            line = line[0..final];
        }
        // Iterate over fields.
        var want: std.ArrayList(Grapheme) = .empty;
        defer want.deinit(allocator);

        var all_bytes: std.ArrayList(u8) = .empty;
        defer all_bytes.deinit(allocator);

        var graphemes = std.mem.splitSequence(u8, line, " ÷ ");
        var bytes_index: uoffset = 0;

        while (graphemes.next()) |field| {
            var code_points = std.mem.splitScalar(u8, field, ' ');
            var cp_buf: [4]u8 = undefined;
            var cp_index: uoffset = 0;
            var gc_len: u8 = 0;

            while (code_points.next()) |code_point| {
                if (std.mem.eql(u8, code_point, "×")) continue;
                const cp: u21 = try std.fmt.parseInt(u21, code_point, 16);
                const len = try unicode.utf8Encode(cp, &cp_buf);
                try all_bytes.appendSlice(allocator, cp_buf[0..len]);
                cp_index += len;
                gc_len += len;
            }

            try want.append(allocator, Grapheme{ .len = gc_len, .offset = bytes_index });
            bytes_index += cp_index;
        }

        const this_str = all_bytes.items;

        {
            var iter = graph.iterator(this_str);

            // Check.
            for (want.items, 1..) |want_gc, idx| {
                const got_gc = (iter.next()).?;
                try std.testing.expectEqualStrings(
                    want_gc.bytes(this_str),
                    got_gc.bytes(this_str),
                );
                for (got_gc.offset..got_gc.offset + got_gc.len) |i| {
                    const this_gc = graph.graphemeAtIndex(this_str, i);
                    std.testing.expectEqualSlices(
                        u8,
                        got_gc.bytes(this_str),
                        this_gc.bytes(this_str),
                    ) catch |err| {
                        debug.print("Wrong grapheme on line {d} #{d} offset {d}\n", .{ line_iter.line, idx, i });
                        return err;
                    };
                }
                var after_iter = graph.iterateAfterGrapheme(this_str, got_gc);
                if (after_iter.next()) |next_gc| {
                    if (iter.peek()) |next_peek| {
                        std.testing.expectEqualSlices(
                            u8,
                            next_gc.bytes(this_str),
                            next_peek.bytes(this_str),
                        ) catch |err| {
                            debug.print("Peeks differ on line {d} #{d} \n", .{ line_iter.line, idx });
                            return err;
                        };
                    } else {
                        debug.print("Mismatch: peek missing, next found, line {d} #{d}\n", .{ line_iter.line, idx });
                        try testing.expect(false);
                    }
                } else {
                    try testing.expectEqual(null, iter.peek());
                }
            }
        }
        {
            var iter = graph.reverseIterator(this_str);

            // Check.
            var i: usize = want.items.len;
            while (i > 0) {
                i -= 1;
                const want_gc = want.items[i];
                const got_gc = iter.prev() orelse {
                    std.debug.print(
                        "line {d} grapheme {d}: expected {any} found null\n",
                        .{ line_iter.line, i, want_gc },
                    );
                    return error.TestExpectedEqual;
                };
                std.testing.expectEqualStrings(
                    want_gc.bytes(this_str),
                    got_gc.bytes(this_str),
                ) catch |err| {
                    std.debug.print(
                        "line {d} grapheme {d}: expected {any} found {any}\n",
                        .{ line_iter.line, i, want_gc, got_gc },
                    );
                    return err;
                };
                var before_iter = graph.iterateBeforeGrapheme(this_str, got_gc);
                if (before_iter.prev()) |prev_gc| {
                    if (iter.peek()) |prev_peek| {
                        std.testing.expectEqualSlices(
                            u8,
                            prev_gc.bytes(this_str),
                            prev_peek.bytes(this_str),
                        ) catch |err| {
                            debug.print("Peeks differ on line {d} #{d} \n", .{ line_iter.line, i });
                            return err;
                        };
                    } else {
                        debug.print("Mismatch: peek missing, prev found, line {d} #{d}\n", .{ line_iter.line, i });
                        try testing.expect(false);
                    }
                } else {
                    try testing.expectEqual(null, iter.peek());
                }
            }
        }
    }
}

test "Segmentation Word Iterator" {
    const allocator = std.testing.allocator;
    const file = try std.fs.cwd().openFile("data/unicode/auxiliary/WordBreakTest.txt", .{});
    defer file.close();

    const content = try readFileContents(allocator, file);
    defer allocator.free(content);

    const wb = try Words.init(allocator);
    defer wb.deinit(allocator);

    var line_iter = LineIterator.init(content);

    while (line_iter.next()) |raw| {
        // Clean up.
        var line = std.mem.trimStart(u8, raw, "÷ ");
        if (std.mem.indexOf(u8, line, " ÷\t")) |final| {
            line = line[0..final];
        }
        // Iterate over fields.
        var want: std.ArrayList(Word) = .empty;
        defer want.deinit(allocator);

        var all_bytes: std.ArrayList(u8) = .empty;
        defer all_bytes.deinit(allocator);

        var words = std.mem.splitSequence(u8, line, " ÷ ");
        var bytes_index: uoffset = 0;

        while (words.next()) |field| {
            var code_points = std.mem.splitScalar(u8, field, ' ');
            var cp_buf: [4]u8 = undefined;
            var cp_index: uoffset = 0;
            var gc_len: u8 = 0;

            while (code_points.next()) |code_point| {
                if (std.mem.eql(u8, code_point, "×")) continue;
                const cp: u21 = try std.fmt.parseInt(u21, code_point, 16);
                const len = try unicode.utf8Encode(cp, &cp_buf);
                try all_bytes.appendSlice(allocator, cp_buf[0..len]);
                cp_index += len;
                gc_len += len;
            }

            try want.append(allocator, Word{ .len = gc_len, .offset = bytes_index });
            bytes_index += cp_index;
        }
        const this_str = all_bytes.items;

        {
            var iter = wb.iterator(this_str);
            var peeked: ?Word = iter.peek();

            // Check.
            for (want.items, 1..) |want_word, idx| {
                const got_word = (iter.next()).?;
                std.testing.expectEqualStrings(
                    want_word.bytes(this_str),
                    got_word.bytes(this_str),
                ) catch |err| {
                    debug.print("Error on line {d}, #{d}\n", .{ line_iter.line, idx });
                    return err;
                };
                std.testing.expectEqualStrings(
                    peeked.?.bytes(this_str),
                    got_word.bytes(this_str),
                ) catch |err| {
                    debug.print("Peek != word on line {d} #{d}\n", .{ line_iter.line, idx });
                    return err;
                };
                var r_iter = iter.reverseIterator();
                const if_r_word = r_iter.prev();
                if (if_r_word) |r_word| {
                    std.testing.expectEqualStrings(
                        want_word.bytes(this_str),
                        r_word.bytes(this_str),
                    ) catch |err| {
                        debug.print("Reversal Error on line {d}, #{d}\n", .{ line_iter.line, idx });
                        return err;
                    };
                } else {
                    try testing.expect(false);
                }
                var peek_iter = wb.iterateAfterWord(this_str, got_word);
                const peek_1 = peek_iter.next();
                if (peek_1) |p1| {
                    const peek_2 = iter.peek();
                    if (peek_2) |p2| {
                        std.testing.expectEqualSlices(
                            u8,
                            p1.bytes(this_str),
                            p2.bytes(this_str),
                        ) catch |err| {
                            debug.print("Bad peek on line {d} #{d} offset {d}\n", .{ line_iter.line, idx + 1, idx });
                            return err;
                        };
                    } else {
                        try testing.expect(false);
                    }
                } else {
                    try testing.expectEqual(null, iter.peek());
                }
                for (got_word.offset..got_word.offset + got_word.len) |i| {
                    const this_word = wb.wordAtIndex(this_str, i);
                    std.testing.expectEqualSlices(
                        u8,
                        got_word.bytes(this_str),
                        this_word.bytes(this_str),
                    ) catch |err| {
                        debug.print("Wrong word on line {d} #{d} offset {d}\n", .{ line_iter.line, idx, i });
                        return err;
                    };
                }
                peeked = iter.peek();
            }
        }
        {
            var r_iter = wb.reverseIterator(this_str);
            var peeked: ?Word = r_iter.peek();
            var idx = want.items.len - 1;

            while (true) : (idx -= 1) {
                const want_word = want.items[idx];
                const got_word = r_iter.prev().?;
                std.testing.expectEqualSlices(
                    u8,
                    want_word.bytes(this_str),
                    got_word.bytes(this_str),
                ) catch |err| {
                    debug.print("Error on line {d}, #{d}\n", .{ line_iter.line, idx + 1 });
                    return err;
                };
                std.testing.expectEqualStrings(
                    peeked.?.bytes(this_str),
                    got_word.bytes(this_str),
                ) catch |err| {
                    debug.print("Peek != word on line {d} #{d}\n", .{ line_iter.line, idx + 1 });
                    return err;
                };
                var f_iter = r_iter.forwardIterator();
                const if_f_word = f_iter.next();
                if (if_f_word) |f_word| {
                    std.testing.expectEqualStrings(
                        want_word.bytes(this_str),
                        f_word.bytes(this_str),
                    ) catch |err| {
                        debug.print("Reversal Error on line {d}, #{d}\n", .{ line_iter.line, idx });
                        return err;
                    };
                } else {
                    try testing.expect(false);
                }
                var peek_iter = wb.iterateBeforeWord(this_str, got_word);
                const peek_1 = peek_iter.prev();
                if (peek_1) |p1| {
                    const peek_2 = r_iter.peek();
                    if (peek_2) |p2| {
                        std.testing.expectEqualSlices(
                            u8,
                            p1.bytes(this_str),
                            p2.bytes(this_str),
                        ) catch |err| {
                            debug.print("Bad peek on line {d} #{d} offset {d}\n", .{ line_iter.line, idx + 1, idx });
                            return err;
                        };
                    } else {
                        try testing.expect(false);
                    }
                } else {
                    try testing.expectEqual(null, r_iter.peek());
                }
                for (got_word.offset..got_word.offset + got_word.len) |i| {
                    const this_word = wb.wordAtIndex(this_str, i);
                    std.testing.expectEqualSlices(
                        u8,
                        got_word.bytes(this_str),
                        this_word.bytes(this_str),
                    ) catch |err| {
                        debug.print("Wrong word on line {d} #{d} offset {d}\n", .{ line_iter.line, idx + 1, i });
                        return err;
                    };
                }
                peeked = r_iter.peek();
                if (idx == 0) break;
            }
        }
    }
}

fn readFileContents(allocator: std.mem.Allocator, file: fs.File) ![]u8 {
    const stat = try file.stat();
    const size = stat.size;
    const content = try allocator.alloc(u8, size);
    errdefer allocator.free(content);

    var total_read: usize = 0;
    while (total_read < size) {
        const bytes_read = try file.read(content[total_read..]);
        if (bytes_read == 0) break;
        total_read += bytes_read;
    }

    return content[0..total_read];
}

const LineIterator = struct {
    content: []const u8,
    pos: usize = 0,
    line: usize = 0,

    fn init(content: []const u8) LineIterator {
        return .{ .content = content };
    }

    fn next(self: *LineIterator) ?[]const u8 {
        while (self.pos < self.content.len) {
            const start = self.pos;
            // Find the # comment delimiter
            var line_end = self.pos;
            while (line_end < self.content.len and self.content[line_end] != '\n' and self.content[line_end] != '#') {
                line_end += 1;
            }

            // Skip to end of line
            while (self.pos < self.content.len and self.content[self.pos] != '\n') {
                self.pos += 1;
            }
            // Skip the newline
            if (self.pos < self.content.len) {
                self.pos += 1;
            }
            self.line += 1;

            // Get the line content (up to #, without trailing \r)
            var line = self.content[start..line_end];
            if (line.len > 0 and line[line.len - 1] == '\r') {
                line = line[0 .. line.len - 1];
            }

            // Skip empty lines and lines starting with @ (but don't trim - test code handles that)
            const trimmed = std.mem.trimEnd(u8, line, " \t\r");
            if (trimmed.len == 0) continue;
            if (trimmed[0] == '@') continue;

            return line;
        }
        return null;
    }
};

const std = @import("std");
const fmt = std.fmt;
const fs = std.fs;
const heap = std.heap;
const mem = std.mem;
const debug = std.debug;
const testing = std.testing;
const unicode = std.unicode;

const uoffset = @FieldType(Word, "offset");

const Grapheme = @import("Graphemes").Grapheme;
const Graphemes = @import("Graphemes");
const GraphemeIterator = @import("Graphemes").Iterator;
const Normalize = @import("Normalize");

const Words = @import("Words");
const Word = Words.Word;
