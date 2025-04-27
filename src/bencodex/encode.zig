const std = @import("std");
const types = @import("types.zig");
const errors = @import("errors.zig");

const Value = types.Value;
const Dictionary = types.Dictionary;
const Key = types.Key;
const Error = errors.Error;
const EncodeError = error{
    EncodingError,
};

fn keyLessThan(context: void, a: Key, b: Key) bool {
    _ = context;

    const a_is_binary = switch (a) {
        .binary => true,
        .text => false,
    };

    const b_is_binary = switch (b) {
        .binary => true,
        .text => false,
    };

    if (a_is_binary and !b_is_binary) {
        return true;
    }

    if (!a_is_binary and b_is_binary) {
        return false;
    }

    return switch (a) {
        .binary => |a_binary| switch (b) {
            .binary => |b_binary| std.mem.lessThan(u8, a_binary, b_binary),
            else => unreachable,
        },
        .text => |a_text| switch (b) {
            .text => |b_text| std.mem.lessThan(u8, a_text, b_text),
            else => unreachable,
        },
    };
}

pub fn encode(writer: std.io.AnyWriter, value: Value) anyerror!void {
    switch (value) {
        .null => writer.writeByte('n') catch return EncodeError.EncodingError,
        .true => writer.writeByte('t') catch return EncodeError.EncodingError,
        .false => writer.writeByte('f') catch return EncodeError.EncodingError,
        .integer => |*i| try encodeInteger(writer, i),
        .binary => |binary| try encodeBinary(writer, binary),
        .text => |text| try encodeText(writer, text),
        .list => |list| try encodeList(writer, list),
        .dictionary => |dict| try encodeDictionary(writer, dict),
    }
}

fn encodeInteger(writer: std.io.AnyWriter, value: *const std.math.big.int.Managed) anyerror!void {
    const allocator = std.heap.page_allocator;
    const string = value.toString(allocator, 10, .lower) catch return Error.MalformedInteger;
    defer allocator.free(string);

    try writer.writeByte('i');
    try writer.writeAll(string);
    try writer.writeByte('e');
}

fn encodeBinary(writer: std.io.AnyWriter, binary: []const u8) !void {
    try std.fmt.formatInt(binary.len, 10, .lower, .{}, writer);
    try writer.writeByte(':');
    try writer.writeAll(binary);
}

fn encodeText(writer: std.io.AnyWriter, text: []const u8) !void {
    if (!std.unicode.utf8ValidateSlice(text)) {
        return Error.InvalidUtf8;
    }

    try writer.writeByte('u');
    try std.fmt.formatInt(text.len, 10, .lower, .{}, writer);
    try writer.writeByte(':');
    try writer.writeAll(text);
}

fn encodeList(writer: std.io.AnyWriter, list: []const Value) !void {
    try writer.writeByte('l');
    for (list) |item| {
        try encode(writer, item);
    }
    try writer.writeByte('e');
}

fn encodeDictionary(writer: std.io.AnyWriter, dict: Dictionary) !void {
    try writer.writeByte('d');

    var keys = std.ArrayList(Key).init(std.heap.page_allocator);
    defer keys.deinit();

    var iterator = dict.iterator();
    while (iterator.next()) |entry| {
        const key_copy: Key = switch (entry.key_ptr.*) {
            .binary => |binary| .{ .binary = binary },
            .text => |text| .{ .text = text },
        };
        try keys.append(key_copy);
    }

    std.sort.pdq(Key, keys.items, {}, keyLessThan);

    for (keys.items) |key| {
        switch (key) {
            .binary => |binary| try encodeBinary(writer, binary),
            .text => |text| try encodeText(writer, text),
        }

        const value = dict.get(key) orelse unreachable;
        try encode(writer, value);
    }

    try writer.writeByte('e');
}

pub fn encodeAlloc(allocator: std.mem.Allocator, value: Value) ![]u8 {
    var list = std.ArrayList(u8).init(allocator);
    errdefer list.deinit();

    try encode(list.writer().any(), value);
    return list.toOwnedSlice();
}
