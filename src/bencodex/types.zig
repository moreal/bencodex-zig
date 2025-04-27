const std = @import("std");

pub const Key = union(enum) {
    const Self = @This();

    /// 바이너리 문자열
    binary: []const u8,

    /// 텍스트 문자열
    text: []const u8,

    /// 키의 해시 값을 계산합니다.
    pub fn hash(self: Key) u64 {
        return switch (self) {
            .binary => |binary| {
                var hasher = std.hash.Wyhash.init(0);
                // 바이너리 키에 대한 특별 구분자 추가
                hasher.update(&[_]u8{'b'});
                hasher.update(binary);
                return hasher.final();
            },
            .text => |text| {
                var hasher = std.hash.Wyhash.init(0);
                // 텍스트 키에 대한 특별 구분자 추가
                hasher.update(&[_]u8{'t'});
                hasher.update(text);
                return hasher.final();
            },
        };
    }

    /// 두 키가 같은지 비교합니다.
    pub fn eql(self: Key, other: Key) bool {
        // 먼저 태그를 비교합니다
        if (@as(std.meta.Tag(Key), self) != @as(std.meta.Tag(Key), other)) {
            return false;
        }

        // 같은 타입이면 내용을 비교합니다
        return switch (self) {
            .binary => |binary| std.mem.eql(u8, binary, other.binary),
            .text => |text| std.mem.eql(u8, text, other.text),
        };
    }

    pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .binary => |binary| allocator.free(binary),
            .text => |text| allocator.free(text),
            else => {},
        }
    }
};

// Dictionary 컨텍스트를 정의합니다
const DictionaryContext = struct {
    pub fn hash(self: @This(), key: Key) u64 {
        _ = self;
        return key.hash();
    }

    pub fn eql(self: @This(), a: Key, b: Key) bool {
        _ = self;
        return a.eql(b);
    }
};

// Dictionary 타입을 정의합니다
pub const Dictionary = std.HashMap(Key, Value, DictionaryContext, std.hash_map.default_max_load_percentage);

/// Bencodex는 다음과 같은 값 타입을 지원합니다:
/// - Null
/// - Boolean
/// - Integer (임의 크기의 정수)
/// - Binary (바이트 문자열)
/// - Text (유니코드 문자열)
/// - List (값들의 리스트)
/// - Dictionary (문자열 키와 값으로 구성된 사전)
pub const Value = union(enum) {
    const Self = @This();

    /// Null 값
    null,

    /// Boolean 값
    boolean: bool,

    /// 정수 값
    integer: std.math.big.int.Managed, // 임의 크기의 정수를 위한 bigint 타입

    /// 바이트 문자열
    binary: []const u8,

    /// 유니코드 문자열
    text: []const u8, // UTF-8로 인코딩된 문자열

    /// 값들의 리스트
    list: []const Value,

    /// 키-값 쌍의 사전
    dictionary: Dictionary,

    /// 리소스를 해제합니다.
    /// 주의: allocator는 Value를 할당하는 데 사용된 것과 동일해야 합니다.
    pub fn deinit(self: *const Self, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .integer => |*integer| {
                @constCast(integer).deinit();
            },
            .binary => |binary| allocator.free(binary),
            .text => |text| allocator.free(text),
            .list => |list| {
                for (list) |item| {
                    item.deinit(allocator);
                }
                allocator.free(list);
            },
            .dictionary => |*dict| @constCast(dict).deinit(),
            else => {}, // null, boolean은 해제할 리소스가 없음
        }
    }

    /// 값의 깊은 복사본을 생성합니다.
    pub fn clone(self: Self, allocator: std.mem.Allocator) !Self {
        return switch (self) {
            .null => .null,
            .boolean => |b| .{ .boolean = b },
            .integer => |*integer| .{
                .integer = try integer.clone(),
            },
            .binary => |binary| .{
                .binary = try allocator.dupe(u8, binary),
            },
            .text => |text| .{
                .text = try allocator.dupe(u8, text),
            },
            .list => |list| blk: {
                var new_list = try allocator.alloc(Value, list.len);
                errdefer allocator.free(new_list);

                for (list, 0..) |item, i| {
                    new_list[i] = try item.clone(allocator);
                    errdefer {
                        for (new_list[0..i]) |prev_item| {
                            prev_item.deinit(allocator);
                        }
                    }
                }

                break :blk .{ .list = new_list };
            },
            .dictionary => |dict| blk: {
                var new_dict = Dictionary.init(allocator);
                errdefer new_dict.deinit();

                var iter = dict.iterator();
                while (iter.next()) |entry| {
                    // 키의 깊은 복사
                    const new_key: Key = switch (entry.key_ptr.*) {
                        .binary => |binary| .{ .binary = try allocator.dupe(u8, binary) },
                        .text => |text| .{ .text = try allocator.dupe(u8, text) },
                    };
                    errdefer new_key.deinit(allocator);

                    // 값의 깊은 복사
                    var new_value = try entry.value_ptr.*.clone(allocator);
                    errdefer new_value.deinit(allocator);

                    // 항목 추가
                    try new_dict.put(new_key, new_value);
                }

                break :blk .{ .dictionary = new_dict };
            },
        };
    }
};
