const std = @import("std");
const types = @import("types.zig");
const errors = @import("errors.zig");
const io = @import("io.zig");

const Key = types.Key;
const Value = types.Value;
const Dictionary = types.Dictionary;
const DictionaryEntry = Dictionary.Entry;
const Error = errors.DecodeError;

fn Parser(comptime ReaderType: type) type {
    comptime io.validateReader(ReaderType);

    return struct {
        reader: ReaderType,
        allocator: std.mem.Allocator,

        const Self = @This();

        fn readByte(self: *Self) !u8 {
            return self.reader.readByte() catch |err| {
                return if (err == error.EndOfStream) Error.UnexpectedEof else err;
            };
        }

        fn readBytes(self: *Self, size: usize) ![]u8 {
            const result = try self.allocator.alloc(u8, size);
            errdefer self.allocator.free(result);

            const bytes_read = try self.reader.readAll(result);
            if (bytes_read < size) {
                return Error.UnexpectedEof;
            }

            return result;
        }
    };
}

pub fn decode(allocator: std.mem.Allocator, reader: anytype) !Value {
    var parser = Parser(@TypeOf(reader)){
        .reader = reader,
        .allocator = allocator,
    };
    return try parseValue(&parser);
}

pub fn decodeAlloc(allocator: std.mem.Allocator, data: []const u8) !Value {
    var fbs = std.io.fixedBufferStream(data);
    return try decode(allocator, fbs.reader());
}

fn parseValue(parser: anytype) anyerror!Value {
    comptime assertParserType(@TypeOf(parser));

    const marker = try parser.readByte();

    return switch (marker) {
        'n' => Value.null,
        't' => Value.true,
        'f' => Value.false,
        'i' => try parseInteger(parser),
        'l' => try parseList(parser),
        'd' => try parseDictionary(parser),
        'u' => try parseText(parser),
        '0'...'9' => try parseBinary(parser, marker),
        else => Error.InvalidFormat,
    };
}

fn parseInteger(parser: anytype) !Value {
    comptime assertParserType(@TypeOf(parser));

    var buf = std.ArrayList(u8).init(parser.allocator);
    defer buf.deinit();

    var first = true;
    var negative = false;

    while (true) {
        const byte = try parser.readByte();
        if (byte == 'e') {
            break;
        }

        if (first) {
            if (byte == '-') {
                negative = true;
                try buf.append(byte);
                first = false;
                continue;
            }
            first = false;
        }

        if (byte < '0' or byte > '9') {
            return Error.MalformedInteger;
        }

        try buf.append(byte);
    }

    if (negative and buf.items.len == 2 and buf.items[1] == '0') {
        return Error.MalformedInteger;
    }

    if (buf.items.len > 1 and buf.items[0] == '0' and !negative) {
        return Error.MalformedInteger;
    }
    if (buf.items.len > 2 and buf.items[0] == '-' and buf.items[1] == '0') {
        return Error.MalformedInteger;
    }

    var integer = try std.math.big.int.Managed.init(parser.allocator);
    errdefer integer.deinit();

    try integer.setString(10, buf.items);

    return Value{ .integer = integer };
}

fn parseBinary(parser: anytype, first_digit: u8) !Value {
    comptime assertParserType(@TypeOf(parser));

    var len_buf = std.ArrayList(u8).init(parser.allocator);
    defer len_buf.deinit();

    try len_buf.append(first_digit);

    while (true) {
        const byte = try parser.readByte();
        if (byte == ':') {
            break;
        }
        if (byte < '0' or byte > '9') {
            return Error.MalformedBinary;
        }
        try len_buf.append(byte);
    }

    const length = std.fmt.parseInt(usize, len_buf.items, 10) catch {
        return Error.MalformedBinary;
    };

    const binary_data = try parser.readBytes(length);

    return Value{ .binary = binary_data };
}

fn parseText(parser: anytype) !Value {
    comptime assertParserType(@TypeOf(parser));

    var len_buf = std.ArrayList(u8).init(parser.allocator);
    defer len_buf.deinit();

    while (true) {
        const byte = try parser.readByte();
        if (byte == ':') {
            break;
        }
        if (byte < '0' or byte > '9') {
            return Error.InvalidFormat;
        }
        try len_buf.append(byte);
    }

    const length = std.fmt.parseInt(usize, len_buf.items, 10) catch {
        return Error.InvalidFormat;
    };

    const text_data = try parser.readBytes(length);
    errdefer parser.allocator.free(text_data);

    if (!std.unicode.utf8ValidateSlice(text_data)) {
        return Error.InvalidUtf8;
    }

    return Value{ .text = text_data };
}

fn parseList(parser: anytype) !Value {
    comptime assertParserType(@TypeOf(parser));

    var items = std.ArrayList(Value).init(parser.allocator);
    errdefer {
        for (items.items) |item| {
            item.deinit(parser.allocator);
        }
        items.deinit();
    }

    while (true) {
        const byte = try parser.readByte();
        if (byte == 'e') {
            break;
        }

        const item = try parseValueWithFirstByte(parser, byte);
        try items.append(item);
    }

    return Value{
        .list = try items.toOwnedSlice(),
    };
}

fn parseDictionary(parser: anytype) !Value {
    comptime assertParserType(@TypeOf(parser));

    var dictionary = Dictionary.init(parser.allocator);
    errdefer dictionary.deinit();

    var has_text_key = false;

    parse_loop: while (true) {
        const next_byte = try parser.readByte();

        if (next_byte == 'e') {
            break :parse_loop;
        }

        var key_value = try parseValueWithFirstByte(parser, next_byte);
        defer {
            if (key_value != .binary and key_value != .text) {
                key_value.deinit(parser.allocator);
            }
        }

        const key: Key = switch (key_value) {
            .binary => |binary| .{ .binary = binary },
            .text => |text| .{ .text = text },
            else => unreachable,
        };

        if (key == .text) {
            has_text_key = true;
        } else if (has_text_key) {
            return Error.MalformedDictionary;
        }

        const value = try parseValue(parser);

        if (dictionary.contains(key)) {
            return Error.MalformedDictionary;
        }

        dictionary.put(key, value) catch return Error.UnknownError;
    }

    return Value{
        .dictionary = dictionary,
    };
}

fn parseValueWithFirstByte(parser: anytype, first_byte: u8) anyerror!Value {
    comptime assertParserType(@TypeOf(parser));

    return switch (first_byte) {
        'n' => Value.null,
        't' => Value.true,
        'f' => Value.false,
        'i' => try parseInteger(parser),
        'l' => try parseList(parser),
        'd' => try parseDictionary(parser),
        'u' => try parseText(parser),
        '0'...'9' => try parseBinary(parser, first_byte),
        else => Error.InvalidFormat,
    };
}

fn assertParserType(comptime T: type) void {
    const T_info = @typeInfo(T);
    const ActualType = switch (T_info) {
        .pointer => |ptr_info| ptr_info.child,
        else => T,
    };

    if (!@hasDecl(ActualType, "readByte") or
        !@hasDecl(ActualType, "readBytes") or
        !@hasField(ActualType, "allocator"))
    {
        @compileError("Parser must have readByte, readBytes methods and allocator field");
    }
}
