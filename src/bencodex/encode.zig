const std = @import("std");
const types = @import("types.zig");
const errors = @import("errors.zig");

const Value = types.Value;
const Dictionary = types.Dictionary;
const Key = types.Key;
const Error = errors.Error;
const EncodeError = error{
    /// 인코딩 중 오류 발생
    EncodingError,
};

// 키 정렬을 위한 비교 함수
fn keyLessThan(context: void, a: Key, b: Key) bool {
    _ = context;

    // 1. 바이너리 문자열이 유니코드 문자열보다 앞에 와야 함
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

    // 2. 같은 타입일 경우 바이트 순서로 비교
    return switch (a) {
        .binary => |a_binary| switch (b) {
            .binary => |b_binary| std.mem.lessThan(u8, a_binary, b_binary),
            else => unreachable, // 이전 조건에서 처리됨
        },
        .text => |a_text| switch (b) {
            .text => |b_text| std.mem.lessThan(u8, a_text, b_text),
            else => unreachable, // 이전 조건에서 처리됨
        },
    };
}

pub fn encode(writer: std.io.AnyWriter, value: Value) anyerror!void {
    switch (value) {
        .null => writer.writeByte('n') catch return EncodeError.EncodingError,
        .boolean => |b| writer.writeByte(if (b) 't' else 'f') catch return EncodeError.EncodingError,
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

    // 스펙에 따라 키를 정렬하기 위해 모든 키를 수집합니다
    var keys = std.ArrayList(Key).init(std.heap.page_allocator);
    defer keys.deinit();

    var iterator = dict.iterator();
    while (iterator.next()) |entry| {
        // 키 복사본을 만듭니다
        const key_copy: Key = switch (entry.key_ptr.*) {
            .binary => |binary| .{ .binary = binary },
            .text => |text| .{ .text = text },
        };
        try keys.append(key_copy);
    }

    // 스펙에 따라 키를 정렬합니다
    std.sort.pdq(Key, keys.items, {}, keyLessThan);

    // 정렬된 순서대로 키와 값을 인코딩합니다
    for (keys.items) |key| {
        switch (key) {
            .binary => |binary| try encodeBinary(writer, binary),
            .text => |text| try encodeText(writer, text),
        }

        const value = dict.get(key) orelse unreachable; // dict에서 가져온 키이므로 항상 존재합니다
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
