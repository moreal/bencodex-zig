# bencodex-zig

A Zig implementation of the Bencodex format. This library provides a simple and efficient API for encoding and decoding Bencodex data.

## What is Bencodex?

[Bencodex](https://github.com/planetarium/bencodex) is a serialization format that extends BitTorrent's [Bencoding](http://www.bittorrent.org/beps/bep_0003.html#bencoding). Every valid Bencoding representation is also a valid Bencodex representation with the same meaning. Bencodex adds the following data types:

- `null` value
- Boolean values (`true`, `false`)
- Unicode strings in addition to byte strings
- Dictionaries that can use both byte strings and Unicode strings as keys

One of Bencodex's key features is forced normalization, where only a single valid encoding exists for each complex value. This allows applications to compare encoded forms directly without decoding the values, which is particularly useful for cryptographic hashing or digital signatures.

## Installation

```bash
# Using zig package manager
zig fetch --save https://github.com/moreal/bencodex-zig/archive/<version>.tar.gz

# Or manually clone and build
git clone https://github.com/moreal/bencodex-zig.git
cd bencodex-zig
zig build
```

## Usage

### Importing

```zig
const bencodex = @import("bencodex-zig");
```

### Encoding

```zig
const std = @import("std");
const bencodex = @import("bencodex-zig");

const Value = bencodex.types.Value;
const encode = bencodex.encode;

pub fn main() !void {
    // Always use explicit allocator
    const allocator = std.heap.page_allocator;
    
    // Create an integer value
    var integer = try std.math.big.int.Managed.init(allocator);
    try integer.setString(10, "123");
    defer integer.deinit();

    // Create a bencodex value
    const value = Value{ .integer = integer };
    
    // Encode the value
    const encoded = try encode.encodeAlloc(allocator, value);
    defer allocator.free(encoded);
    
    // Print the result
    std.debug.print("{s}\n", .{encoded}); // Output: i123e
}
```

### Decoding

```zig
const std = @import("std");
const bencodex = @import("bencodex-zig");

const decode = bencodex.decode;

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    
    // Bencodex data
    const data = "i123e";
    
    // Decode
    const value = try decode.decodeAlloc(allocator, data);
    defer value.deinit(allocator);
    
    // Use the value
    switch (value) {
        .integer => |*i| {
            const str = try i.toString(allocator, 10, .lower);
            defer allocator.free(str);
            std.debug.print("Integer: {s}\n", .{str}); // Output: Integer: 123
        },
        else => std.debug.print("Other type\n", .{}),
    }
}
```

### Creating Complex Values

```zig
const std = @import("std");
const bencodex = @import("bencodex-zig");

const Value = bencodex.types.Value;
const Key = bencodex.types.Key;
const Dictionary = bencodex.types.Dictionary;

pub fn createComplexValue(allocator: std.mem.Allocator) !Value {
    // Create a dictionary
    var dict = Dictionary.init(allocator);
    errdefer dict.deinit();
    
    // Add text key with integer value
    {
        const key = Key{ .text = "age" };
        var integer = try std.math.big.int.Managed.init(allocator);
        try integer.setString(10, "30");
        const value = Value{ .integer = integer };
        try dict.put(key, value);
    }
    
    // Add binary key with text value
    {
        const key = Key{ .binary = "raw_data" };
        const value = Value{ .text = "Hello, world!" };
        try dict.put(key, value);
    }
    
    // Add a list
    {
        const key = Key{ .text = "items" };
        var list = try allocator.alloc(Value, 3);
        
        list[0] = Value{ .text = "item1" };
        list[1] = Value{ .null = {} };
        list[2] = Value{ .true = {} };
        
        const value = Value{ .list = list };
        try dict.put(key, value);
    }
    
    return Value{ .dictionary = dict };
}
```

## Supported Data Types

- `null` - Null value
- `true`, `false` - Boolean values
- `integer` - Arbitrary precision integer
- `binary` - Byte string
- `text` - Unicode string
- `list` - List of values
- `dictionary` - Collection of key-value pairs (lexicographically ordered)

## Error Handling

The library uses Zig's error union types for functions that can fail:

```zig
const DecodingError = error{
    InvalidFormat,
    UnexpectedEOF,
    UnexpectedToken,
    // Other specific errors...
};

pub fn decode(reader: anytype) !Value {
    // Implementation that returns a value or an error
}
```

## Memory Management

Most functions in this library accept an allocator and return allocated resources. It's the caller's responsibility to free these resources:

```zig
// Allocate a value
const value = try decode.decodeAlloc(allocator, data);
// Free the value when done
defer value.deinit(allocator);
```

## Testing

```bash
zig build test
```

This library includes a comprehensive test suite that validates compliance with the Bencodex specification.

## License

This project is distributed under the [LICENSE_NAME] license. See the LICENSE file for details.

## References

- [Bencodex Specification](https://github.com/planetarium/bencodex) - Official Bencodex specification and test suite
