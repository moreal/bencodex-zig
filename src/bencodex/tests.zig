const std = @import("std");
const testing = std.testing;
const fs = std.fs;
const Allocator = std.mem.Allocator;
const BigInt = std.math.big.int.Managed;
const print = std.debug.print;

const types = @import("types.zig");
const encode = @import("encode.zig");
const decode = @import("decode.zig");

const Value = types.Value;
const Key = types.Key;
const Dictionary = types.Dictionary;

const TESTSUITE_DIR = "spec/testsuite";

const TestData = struct {
    name: []const u8,
    dat_path: []const u8,
    yaml_path: []const u8,
    json_path: []const u8,
};

fn bigIntFromString(allocator: Allocator, value: []const u8) !BigInt {
    var integer = try BigInt.init(allocator);
    errdefer integer.deinit();
    try integer.setString(10, value);
    return integer;
}

fn getTestFiles(allocator: Allocator) ![]TestData {
    var test_files = std.ArrayList(TestData).init(allocator);
    defer test_files.deinit();

    var dir = try fs.cwd().openDir(TESTSUITE_DIR, .{ .iterate = true });
    defer dir.close();

    var it = dir.iterate();
    while (try it.next()) |entry| {
        if (entry.kind != .file) continue;

        if (std.mem.endsWith(u8, entry.name, ".dat")) {
            const base_name = entry.name[0 .. entry.name.len - 4];

            const dat_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ TESTSUITE_DIR, entry.name });
            const yaml_path = try std.fmt.allocPrint(allocator, "{s}/{s}.yaml", .{ TESTSUITE_DIR, base_name });
            const json_path = try std.fmt.allocPrint(allocator, "{s}/{s}.json", .{ TESTSUITE_DIR, base_name });

            try test_files.append(TestData{
                .name = try allocator.dupe(u8, base_name),
                .dat_path = dat_path,
                .yaml_path = yaml_path,
                .json_path = json_path,
            });
        }
    }

    return test_files.toOwnedSlice();
}

fn readDatFile(allocator: Allocator, path: []const u8) ![]u8 {
    const file = try fs.cwd().openFile(path, .{});
    defer file.close();

    const file_size = (try file.stat()).size;
    const content = try allocator.alloc(u8, file_size);
    errdefer allocator.free(content);

    const bytes_read = try file.readAll(content);
    if (bytes_read != file_size) {
        return error.ShortRead;
    }

    return content;
}

test "Run Bencodex testsuite" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const test_files = try getTestFiles(allocator);

    print("\nRunning {d} testsuite files:\n", .{test_files.len});
    for (test_files) |test_data| {
        print("Test: {s}...", .{test_data.name});

        const encoded_data = try readDatFile(allocator, test_data.dat_path);

        const value = try decode.decodeAlloc(allocator, encoded_data);
        defer value.deinit(allocator);

        const reencoded_data = try encode.encodeAlloc(allocator, value);
        defer allocator.free(reencoded_data);

        try testing.expectEqualSlices(u8, encoded_data, reencoded_data);

        print("OK\n", .{});
    }
}

test "null value" {
    const allocator = testing.allocator;

    const value = Value{ .null = {} };
    const encoded = try encode.encodeAlloc(allocator, value);
    defer allocator.free(encoded);

    try testing.expectEqualSlices(u8, "n", encoded);

    const decoded = try decode.decodeAlloc(allocator, encoded);
    try testing.expectEqual(Value.null, decoded);
}

test "boolean value" {
    const allocator = testing.allocator;

    {
        const value = Value{ .boolean = true };
        const encoded = try encode.encodeAlloc(allocator, value);
        defer allocator.free(encoded);

        try testing.expectEqualSlices(u8, "t", encoded);

        const decoded = try decode.decodeAlloc(allocator, encoded);
        try testing.expectEqual(true, decoded.boolean);
    }

    {
        const value = Value{ .boolean = false };
        const encoded = try encode.encodeAlloc(allocator, value);
        defer allocator.free(encoded);

        try testing.expectEqualSlices(u8, "f", encoded);

        const decoded = try decode.decodeAlloc(allocator, encoded);
        try testing.expectEqual(false, decoded.boolean);
    }
}

test "integer value" {
    const allocator = testing.allocator;

    {
        const value = Value{ .integer = try bigIntFromString(allocator, "123") };
        defer value.deinit(allocator);
        const encoded = try encode.encodeAlloc(allocator, value);
        defer allocator.free(encoded);

        try testing.expectEqualSlices(u8, "i123e", encoded);

        const decoded = try decode.decodeAlloc(allocator, encoded);
        defer decoded.deinit(allocator);

        const expected = try bigIntFromString(allocator, "123");
        defer @constCast(&expected).deinit();

        try testing.expect(decoded == .integer);
        try testing.expect(expected.eql(decoded.integer));
    }

    {
        const value = Value{ .integer = try bigIntFromString(allocator, "-456") };
        defer value.deinit(allocator);
        const encoded = try encode.encodeAlloc(allocator, value);
        defer allocator.free(encoded);

        try testing.expectEqualSlices(u8, "i-456e", encoded);

        const decoded = try decode.decodeAlloc(allocator, encoded);
        defer decoded.deinit(allocator);

        const expected = try bigIntFromString(allocator, "-456");
        defer @constCast(&expected).deinit();

        try testing.expect(switch (decoded) {
            .integer => true,
            else => false,
        });
        try testing.expect(expected.eql(decoded.integer));
    }

    {
        const value = Value{ .integer = try bigIntFromString(allocator, "0") };
        defer value.deinit(allocator);
        const encoded = try encode.encodeAlloc(allocator, value);
        defer allocator.free(encoded);

        try testing.expectEqualSlices(u8, "i0e", encoded);

        const decoded = try decode.decodeAlloc(allocator, encoded);
        defer decoded.deinit(allocator);

        const expected = try bigIntFromString(allocator, "0");
        defer @constCast(&expected).deinit();

        try testing.expect(switch (decoded) {
            .integer => true,
            else => false,
        });
        try testing.expect(expected.eql(decoded.integer));
    }

    {
        const value = Value{ .integer = try bigIntFromString(allocator, "9223372036854775807123456789") };
        defer value.deinit(allocator);
        const encoded = try encode.encodeAlloc(allocator, value);
        defer allocator.free(encoded);

        try testing.expectEqualSlices(u8, "i9223372036854775807123456789e", encoded);

        const decoded = try decode.decodeAlloc(allocator, encoded);
        defer decoded.deinit(allocator);

        const expected = try bigIntFromString(allocator, "9223372036854775807123456789");
        defer @constCast(&expected).deinit();

        try testing.expect(switch (decoded) {
            .integer => true,
            else => false,
        });
        try testing.expect(expected.eql(decoded.integer));
    }
}

test "binary string" {
    const allocator = testing.allocator;

    {
        const data = "Hello, world!";
        const value = Value{ .binary = data };
        const encoded = try encode.encodeAlloc(allocator, value);
        defer allocator.free(encoded);

        try testing.expectEqualSlices(u8, "13:Hello, world!", encoded);

        const decoded = try decode.decodeAlloc(allocator, encoded);
        defer decoded.deinit(allocator);
        try testing.expectEqualSlices(u8, data, decoded.binary);
    }

    {
        const data = "";
        const value = Value{ .binary = data };
        const encoded = try encode.encodeAlloc(allocator, value);
        defer allocator.free(encoded);

        try testing.expectEqualSlices(u8, "0:", encoded);

        const decoded = try decode.decodeAlloc(allocator, encoded);
        defer decoded.deinit(allocator);
        try testing.expectEqualSlices(u8, data, decoded.binary);
    }
}

test "text string" {
    const allocator = testing.allocator;

    {
        const text = "Hello, world!";
        const value = Value{ .text = text };
        const encoded = try encode.encodeAlloc(allocator, value);
        defer allocator.free(encoded);

        try testing.expectEqualSlices(u8, "u13:Hello, world!", encoded);

        const decoded = try decode.decodeAlloc(allocator, encoded);
        defer decoded.deinit(allocator);
        try testing.expectEqualSlices(u8, text, decoded.text);
    }

    {
        const text = "안녕, 세계!";
        const value = Value{ .text = text };
        const encoded = try encode.encodeAlloc(allocator, value);
        defer allocator.free(encoded);

        try testing.expectEqualSlices(u8, "u15:안녕, 세계!", encoded);

        const decoded = try decode.decodeAlloc(allocator, encoded);
        defer decoded.deinit(allocator);
        try testing.expectEqualSlices(u8, text, decoded.text);
    }
}

test "list" {
    const allocator = testing.allocator;

    var integer = try BigInt.init(allocator);
    try integer.setString(10, "42");
    defer integer.deinit();

    var items = [_]Value{
        Value{ .null = {} },
        Value{ .boolean = true },
        Value{ .integer = integer },
        Value{ .binary = "hello" },
        Value{ .text = "world" },
    };

    const value = Value{ .list = &items };
    const encoded = try encode.encodeAlloc(allocator, value);
    defer allocator.free(encoded);

    try testing.expectEqualSlices(u8, "lnti42e5:hellou5:worlde", encoded);

    const decoded = try decode.decodeAlloc(allocator, encoded);
    defer decoded.deinit(allocator);

    try testing.expectEqual(@as(usize, 5), decoded.list.len);
    try testing.expectEqual(Value.null, decoded.list[0]);
    try testing.expectEqual(true, decoded.list[1].boolean);

    var expected = try BigInt.init(allocator);
    defer expected.deinit();
    try expected.setString(10, "42");

    try testing.expect(decoded.list[2] == .integer);
    try testing.expect(expected.eql(decoded.list[2].integer));

    try testing.expectEqualSlices(u8, "hello", decoded.list[3].binary);
    try testing.expectEqualSlices(u8, "world", decoded.list[4].text);
}

test "dictionary" {
    const allocator = testing.allocator;

    var int1 = try BigInt.init(allocator);
    try int1.setString(10, "1");
    defer int1.deinit();

    var int2 = try BigInt.init(allocator);
    try int2.setString(10, "2");
    defer int2.deinit();

    var int3 = try BigInt.init(allocator);
    try int3.setString(10, "3");
    defer int3.deinit();

    var dict = Dictionary.init(allocator);
    defer dict.deinit();
    try dict.put(Key{ .binary = "a" }, Value{ .integer = int1 });
    try dict.put(Key{ .binary = "b" }, Value{ .integer = int2 });
    try dict.put(Key{ .text = "c" }, Value{ .integer = int3 });

    const value = Value{ .dictionary = dict };
    const encoded = try encode.encodeAlloc(allocator, value);
    defer allocator.free(encoded);

    try testing.expectEqualSlices(u8, "d1:ai1e1:bi2eu1:ci3ee", encoded);
}
