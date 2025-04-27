const std = @import("std");
const types = @import("types.zig");
const errors = @import("errors.zig");
const io = @import("io.zig");

const Key = types.Key;
const Value = types.Value;
const Dictionary = types.Dictionary;
const DictionaryEntry = Dictionary.Entry;
const Error = errors.Error;

/// 저수준 파서 상태를 관리합니다.
fn Parser(comptime ReaderType: type) type {
    // Reader 타입이 필요한 인터페이스를 갖추고 있는지 컴파일 타임에 검증
    comptime io.validateReader(ReaderType);

    return struct {
        reader: ReaderType,
        allocator: std.mem.Allocator,

        const Self = @This();

        /// 현재 파서 위치에서 단일 바이트를 읽습니다.
        fn readByte(self: *Self) !u8 {
            return self.reader.readByte() catch |err| {
                return if (err == error.EndOfStream) Error.UnexpectedEof else err;
            };
        }

        /// 현재 파서 위치에서 지정된 크기만큼 바이트를 읽습니다.
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

/// Bencodex 데이터를 디코딩합니다.
/// 주어진 reader에서 Bencodex 인코딩된 데이터를 읽고 해당하는 Value를 반환합니다.
/// 할당된 메모리는 반환된 값에 포함되며, 사용이 끝나면 `value.deinit(allocator)`를 호출해야 합니다.
pub fn decode(allocator: std.mem.Allocator, reader: anytype) !Value {
    var parser = Parser(@TypeOf(reader)){
        .reader = reader,
        .allocator = allocator,
    };
    return try parseValue(&parser);
}

/// 바이트 배열을 디코딩합니다.
pub fn decodeAlloc(allocator: std.mem.Allocator, data: []const u8) !Value {
    var fbs = std.io.fixedBufferStream(data);
    return try decode(allocator, fbs.reader());
}

/// Bencodex 값을 재귀적으로 파싱합니다.
fn parseValue(parser: anytype) anyerror!Value {
    comptime assertParserType(@TypeOf(parser));

    const marker = try parser.readByte();

    return switch (marker) {
        'n' => Value{ .null = {} },
        't' => Value{ .boolean = true },
        'f' => Value{ .boolean = false },
        'i' => try parseInteger(parser),
        'l' => try parseList(parser),
        'd' => try parseDictionary(parser),
        'u' => try parseText(parser),
        '0'...'9' => try parseBinary(parser, marker),
        else => Error.InvalidFormat,
    };
}

/// 정수 값을 파싱합니다. 형식: i<정수>e
fn parseInteger(parser: anytype) !Value {
    comptime assertParserType(@TypeOf(parser));

    var buf = std.ArrayList(u8).init(parser.allocator);
    defer buf.deinit();

    // 종료 'e' 표시자가 나올 때까지 정수 문자를 읽습니다
    var first = true;
    var negative = false;

    while (true) {
        const byte = try parser.readByte();
        if (byte == 'e') {
            break;
        }

        // 첫 번째 문자인 경우 음수 기호 확인
        if (first) {
            if (byte == '-') {
                negative = true;
                try buf.append(byte);
                first = false;
                continue;
            }
            first = false;
        }

        // 숫자만 허용합니다
        if (byte < '0' or byte > '9') {
            return Error.MalformedInteger;
        }

        try buf.append(byte);
    }

    // "i-0e"는 유효하지 않습니다 (음수 0)
    if (negative and buf.items.len == 2 and buf.items[1] == '0') {
        return Error.MalformedInteger;
    }

    // "i03e"와 같은 선행 0도 유효하지 않습니다 (i0e는 제외)
    if (buf.items.len > 1 and buf.items[0] == '0' and !negative) {
        return Error.MalformedInteger;
    }
    if (buf.items.len > 2 and buf.items[0] == '-' and buf.items[1] == '0') {
        return Error.MalformedInteger;
    }

    // big.Int를 사용하여 정수 생성
    var integer = try std.math.big.int.Managed.init(parser.allocator);
    errdefer integer.deinit();

    // 숫자 문자열을 big.Int로 파싱
    try integer.setString(10, buf.items);

    return Value{ .integer = integer };
}

/// 바이너리 문자열을 파싱합니다. 형식: <길이>:<데이터>
fn parseBinary(parser: anytype, first_digit: u8) !Value {
    comptime assertParserType(@TypeOf(parser));

    var len_buf = std.ArrayList(u8).init(parser.allocator);
    defer len_buf.deinit();

    // 첫 번째 숫자 추가
    try len_buf.append(first_digit);

    // ':' 구분자가 나올 때까지 나머지 길이 숫자 읽기
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

    // 길이 파싱
    const length = std.fmt.parseInt(usize, len_buf.items, 10) catch {
        return Error.MalformedBinary;
    };

    // 지정된 길이만큼 바이너리 데이터 읽기
    const binary_data = try parser.readBytes(length);

    return Value{ .binary = binary_data };
}

/// 유니코드 텍스트 문자열을 파싱합니다. 형식: u<길이>:<UTF-8 데이터>
fn parseText(parser: anytype) !Value {
    comptime assertParserType(@TypeOf(parser));

    var len_buf = std.ArrayList(u8).init(parser.allocator);
    defer len_buf.deinit();

    // ':' 구분자가 나올 때까지 길이 숫자 읽기
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

    // 길이 파싱
    const length = std.fmt.parseInt(usize, len_buf.items, 10) catch {
        return Error.InvalidFormat;
    };

    // 지정된 길이만큼 UTF-8 데이터 읽기
    const text_data = try parser.readBytes(length);
    errdefer parser.allocator.free(text_data);

    // UTF-8 유효성 확인
    if (!std.unicode.utf8ValidateSlice(text_data)) {
        return Error.InvalidUtf8;
    }

    return Value{ .text = text_data };
}

/// 리스트를 파싱합니다. 형식: l<항목들>e
fn parseList(parser: anytype) !Value {
    comptime assertParserType(@TypeOf(parser));

    var items = std.ArrayList(Value).init(parser.allocator);
    errdefer {
        for (items.items) |item| {
            item.deinit(parser.allocator);
        }
        items.deinit();
    }

    // 종료 'e' 표시자가 나올 때까지 항목 파싱
    while (true) {
        const byte = try parser.readByte();
        if (byte == 'e') {
            break;
        }

        // 'e'가 아니면 값으로 파싱
        const item = try parseValueWithFirstByte(parser, byte);
        try items.append(item);
    }

    // 항목들을 포함한 리스트 반환
    return Value{
        .list = try items.toOwnedSlice(),
    };
}

/// 사전을 파싱합니다. 형식: d<키-값 쌍>e
fn parseDictionary(parser: anytype) !Value {
    comptime assertParserType(@TypeOf(parser));

    var dictionary = Dictionary.init(parser.allocator);
    errdefer dictionary.deinit();

    var has_text_key = false;

    // 종료 'e' 표시자가 나올 때까지 키-값 쌍 파싱
    parse_loop: while (true) {
        // 다음 바이트 읽기
        const next_byte = try parser.readByte();

        // 종료 문자 확인
        if (next_byte == 'e') {
            break :parse_loop;
        }

        // 키 처리 (첫 바이트가 이미 읽힘)
        var key_value = try parseValueWithFirstByte(parser, next_byte);
        defer {
            // 키는 바이너리 또는 텍스트 문자열이어야 함
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

        // 값 파싱
        const value = try parseValue(parser);

        if (dictionary.contains(key)) {
            return Error.MalformedDictionary;
        }

        dictionary.put(key, value) catch return Error.UnknownError;
    }

    // 항목들을 포함한 사전 반환
    return Value{
        .dictionary = dictionary,
    };
}

/// 첫 바이트를 이미 읽은 경우 값을 파싱합니다.
fn parseValueWithFirstByte(parser: anytype, first_byte: u8) anyerror!Value {
    comptime assertParserType(@TypeOf(parser));

    return switch (first_byte) {
        'n' => Value{ .null = {} },
        't' => Value{ .boolean = true },
        'f' => Value{ .boolean = false },
        'i' => try parseInteger(parser),
        'l' => try parseList(parser),
        'd' => try parseDictionary(parser),
        'u' => try parseText(parser),
        '0'...'9' => try parseBinary(parser, first_byte),
        else => Error.InvalidFormat,
    };
}

/// 컴파일 타임에 파서 타입이 필요한 메서드와 필드를 가지고 있는지 검사합니다.
fn assertParserType(comptime T: type) void {
    const T_info = @typeInfo(T);
    const ActualType = switch (T_info) {
        .pointer => |ptr_info| ptr_info.child,
        else => T,
    };

    // Check against the actual type (pointee type if T is a pointer)
    if (!@hasDecl(ActualType, "readByte") or
        !@hasDecl(ActualType, "readBytes") or
        !@hasField(ActualType, "allocator"))
    {
        @compileError("Parser must have readByte, readBytes methods and allocator field");
    }
}
