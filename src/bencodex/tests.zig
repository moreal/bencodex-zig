const std = @import("std");
const testing = std.testing;
const fs = std.fs;
const Allocator = std.mem.Allocator;
const print = std.debug.print;

const types = @import("types.zig");
const encode = @import("encode.zig");
const decode = @import("decode.zig");

const Value = types.Value;
const Dictionary = types.Dictionary;

/// 테스트 스위트 디렉토리 경로
const TESTSUITE_DIR = "spec/testsuite";

/// 테스트 데이터를 위한 구조체
const TestData = struct {
    name: []const u8,
    dat_path: []const u8,
    yaml_path: []const u8,
    json_path: []const u8,
};

/// 테스트 파일 목록을 얻는 함수
fn getTestFiles(allocator: Allocator) ![]TestData {
    var test_files = std.ArrayList(TestData).init(allocator);
    defer test_files.deinit();

    // 디렉토리 열기
    var dir = try fs.cwd().openDir(TESTSUITE_DIR, .{ .iterate = true });
    defer dir.close();

    // 모든 .dat 파일을 찾아 TestData 생성
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

/// .dat 파일에서 인코딩된 Bencodex 데이터를 읽는 함수
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
    // 테스트 메모리 할당자 사용
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // 테스트 파일 목록 얻기
    const test_files = try getTestFiles(allocator);

    // 개별 테스트 실행
    print("\nRunning {d} testsuite files:\n", .{test_files.len});
    for (test_files) |test_data| {
        print("Test: {s}...", .{test_data.name});

        // .dat 파일에서 인코딩된 데이터 읽기
        const encoded_data = try readDatFile(allocator, test_data.dat_path);

        // 디코딩
        const value = try decode.decodeAlloc(allocator, encoded_data);

        // 인코딩
        const reencoded_data = try encode.encodeAlloc(allocator, value);
        defer allocator.free(reencoded_data);

        // 원본과 재인코딩된 데이터가 일치하는지 확인
        try testing.expectEqualSlices(u8, encoded_data, reencoded_data);

        print("OK\n", .{});
    }
}

test "null value" {
    // null value 테스트
    const allocator = testing.allocator;

    const value = Value{ .null_value = {} };
    const encoded = try encode.encodeAlloc(allocator, value);
    defer allocator.free(encoded);

    try testing.expectEqualSlices(u8, "n", encoded);

    const decoded = try decode.decodeAlloc(allocator, encoded);
    try testing.expectEqual(Value.null_value, decoded);
}

test "boolean value" {
    const allocator = testing.allocator;

    // true 테스트
    {
        const value = Value{ .boolean = true };
        const encoded = try encode.encodeAlloc(allocator, value);
        defer allocator.free(encoded);

        try testing.expectEqualSlices(u8, "t", encoded);

        const decoded = try decode.decodeAlloc(allocator, encoded);
        try testing.expectEqual(true, decoded.boolean);
    }

    // false 테스트
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

    // 양수 테스트
    {
        const value = Value{ .integer = 123 };
        const encoded = try encode.encodeAlloc(allocator, value);
        defer allocator.free(encoded);

        try testing.expectEqualSlices(u8, "i123e", encoded);

        const decoded = try decode.decodeAlloc(allocator, encoded);
        try testing.expectEqual(@as(i64, 123), decoded.integer);
    }

    // 음수 테스트
    {
        const value = Value{ .integer = -456 };
        const encoded = try encode.encodeAlloc(allocator, value);
        defer allocator.free(encoded);

        try testing.expectEqualSlices(u8, "i-456e", encoded);

        const decoded = try decode.decodeAlloc(allocator, encoded);
        try testing.expectEqual(@as(i64, -456), decoded.integer);
    }

    // 0 테스트
    {
        const value = Value{ .integer = 0 };
        const encoded = try encode.encodeAlloc(allocator, value);
        defer allocator.free(encoded);

        try testing.expectEqualSlices(u8, "i0e", encoded);

        const decoded = try decode.decodeAlloc(allocator, encoded);
        try testing.expectEqual(@as(i64, 0), decoded.integer);
    }
}

test "binary string" {
    const allocator = testing.allocator;

    // 일반 바이너리 문자열 테스트
    {
        const data = "Hello, world!";
        const value = Value{ .binary = data };
        const encoded = try encode.encodeAlloc(allocator, value);
        defer allocator.free(encoded);

        try testing.expectEqualSlices(u8, "13:Hello, world!", encoded);

        const decoded = try decode.decodeAlloc(allocator, encoded);
        try testing.expectEqualSlices(u8, data, decoded.binary);
    }

    // 비어있는 바이너리 문자열 테스트
    {
        const data = "";
        const value = Value{ .binary = data };
        const encoded = try encode.encodeAlloc(allocator, value);
        defer allocator.free(encoded);

        try testing.expectEqualSlices(u8, "0:", encoded);

        const decoded = try decode.decodeAlloc(allocator, encoded);
        try testing.expectEqualSlices(u8, data, decoded.binary);
    }
}

test "text string" {
    const allocator = testing.allocator;

    // ASCII 텍스트 테스트
    {
        const text = "Hello, world!";
        const value = Value{ .text = text };
        const encoded = try encode.encodeAlloc(allocator, value);
        defer allocator.free(encoded);

        try testing.expectEqualSlices(u8, "u13:Hello, world!", encoded);

        const decoded = try decode.decodeAlloc(allocator, encoded);
        try testing.expectEqualSlices(u8, text, decoded.text);
    }

    // 유니코드 텍스트 테스트
    {
        const text = "안녕, 세계!"; // UTF-8 인코딩된 한글
        const value = Value{ .text = text };
        const encoded = try encode.encodeAlloc(allocator, value);
        defer allocator.free(encoded);

        try testing.expectEqualSlices(u8, "u14:안녕, 세계!", encoded);

        const decoded = try decode.decodeAlloc(allocator, encoded);
        try testing.expectEqualSlices(u8, text, decoded.text);
    }
}

test "list" {
    const allocator = testing.allocator;

    // 여러 타입을 포함한 리스트 테스트
    var items = [_]Value{
        Value{ .null_value = {} },
        Value{ .boolean = true },
        Value{ .integer = 42 },
        Value{ .binary = "hello" },
        Value{ .text = "world" },
    };

    const value = Value{ .list = &items };
    const encoded = try encode.encodeAlloc(allocator, value);
    defer allocator.free(encoded);

    try testing.expectEqualSlices(u8, "lnti42e5:hellou5:worlde", encoded);

    const decoded = try decode.decodeAlloc(allocator, encoded);
    defer {
        for (decoded.list) |item| {
            item.deinit(allocator);
        }
        allocator.free(decoded.list);
    }

    try testing.expectEqual(@as(usize, 5), decoded.list.len);
    try testing.expectEqual(Value.null_value, decoded.list[0]);
    try testing.expectEqual(true, decoded.list[1].boolean);
    try testing.expectEqual(@as(i64, 42), decoded.list[2].integer);
    try testing.expectEqualSlices(u8, "hello", decoded.list[3].binary);
    try testing.expectEqualSlices(u8, "world", decoded.list[4].text);
}

test "dictionary" {
    const allocator = testing.allocator;

    var entries = [_]Dictionary.Entry{
        .{
            .key = .{ .binary = "a" },
            .value = Value{ .integer = 1 },
        },
        .{
            .key = .{ .binary = "b" },
            .value = Value{ .integer = 2 },
        },
        .{
            .key = .{ .text = "c" },
            .value = Value{ .integer = 3 },
        },
    };

    const dict = Dictionary{ .entries = &entries };
    const value = Value{ .dictionary = dict };
    const encoded = try encode.encodeAlloc(allocator, value);
    defer allocator.free(encoded);

    try testing.expectEqualSlices(u8, "d1:ai1e1:bi2eu1:ci3ee", encoded);
    try testing.expectEqual(false, true);
}
