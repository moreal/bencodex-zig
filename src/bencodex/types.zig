const std = @import("std");

pub const Key = union(enum) {
    const Self = @This();

    binary: []const u8,

    text: []const u8,

    pub fn hash(self: Key) u64 {
        return switch (self) {
            .binary => |binary| {
                var hasher = std.hash.Wyhash.init(0);
                hasher.update(&[_]u8{'b'});
                hasher.update(binary);
                return hasher.final();
            },
            .text => |text| {
                var hasher = std.hash.Wyhash.init(0);
                hasher.update(&[_]u8{'t'});
                hasher.update(text);
                return hasher.final();
            },
        };
    }

    pub fn eql(self: Key, other: Key) bool {
        if (@as(std.meta.Tag(Key), self) != @as(std.meta.Tag(Key), other)) {
            return false;
        }

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

pub const Dictionary = std.HashMap(Key, Value, DictionaryContext, std.hash_map.default_max_load_percentage);

pub const Value = union(enum) {
    const Self = @This();

    null,

    boolean: bool,

    integer: std.math.big.int.Managed,

    binary: []const u8,

    text: []const u8,

    list: []const Value,

    dictionary: Dictionary,

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
            else => {},
        }
    }

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
                    const new_key: Key = switch (entry.key_ptr.*) {
                        .binary => |binary| .{ .binary = try allocator.dupe(u8, binary) },
                        .text => |text| .{ .text = try allocator.dupe(u8, text) },
                    };
                    errdefer new_key.deinit(allocator);

                    var new_value = try entry.value_ptr.*.clone(allocator);
                    errdefer new_value.deinit(allocator);

                    try new_dict.put(new_key, new_value);
                }

                break :blk .{ .dictionary = new_dict };
            },
        };
    }
};
