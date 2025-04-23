# Copilot Instructions for Zig Project

## Project Overview

This is a Zig project that follows idiomatic Zig practices and standards. The following instructions will help you contribute effectively to the codebase.

## Coding Standards

### General Guidelines

- Follow the [Zig Style Guide](https://ziglang.org/documentation/master/#Style-Guide)
- Use Zig's standard library where appropriate
- Prioritize readability and simplicity over cleverness
- Write code that is easy to test and maintain
- Keep functions small and focused on a single task
- Use meaningful variable and function names

### Memory Management

- Prefer explicit allocators over implicit ones
- Always handle allocation failures appropriately
- Free memory resources when they are no longer needed
- Use `defer` for cleanup operations where appropriate
- Consider using arenas for related allocations

### Error Handling

- Use Zig's error union types for functions that can fail
- Handle all errors explicitly, avoid ignoring error values
- Use `try` for propagating errors up the call stack
- Provide meaningful error messages and context
- Create custom error sets where appropriate

### Types and Data Structures

- Use the most specific type possible
- Prefer slices over pointers when working with arrays
- Use structs with clear semantics
- Leverage comptime for generic code where beneficial
- Consider using tagged unions for variant data

## Project Structure

```
src/
├── main.zig           # Application entry point
├── components/        # Core components of the application
├── utils/             # Utility functions and helpers
├── tests/             # Test files
└── build.zig          # Build script
```

## Build System

This project uses Zig's built-in build system. To build the project:

```bash
zig build
```

To run tests:

```bash
zig build test
```

## Documentation

- Document public functions and types with doc comments
- Use `///` for doc comments
- Explain parameters, return values, and error conditions
- Provide examples in doc comments for complex functions
- Keep internal implementation details documented with regular comments `//`

## Testing

- Write tests for all public functionality
- Name test functions descriptively
- Use the standard test framework
- Structure tests with clear setup, execution, and verification sections
- Consider edge cases and error conditions

## Recommended Development Environment

- Zig Language Server for IDE integration
- zls for code completion and diagnostics
- Use `zig fmt` to format code consistently

## Common Patterns

### Resource Management

```zig
fn example() !void {
    const file = try std.fs.cwd().openFile("example.txt", .{});
    defer file.close();
    
    // Work with file
}
```

### Error Handling

```zig
fn readConfig(allocator: std.mem.Allocator) !Config {
    const file = std.fs.cwd().openFile("config.json", .{}) catch |err| {
        std.log.err("Failed to open config file: {}", .{err});
        return err;
    };
    defer file.close();
    
    // Process file
}
```

### Options Patterns

```zig
const Options = struct {
    timeout_ms: u32 = 1000,
    max_retries: u8 = 3,
    verbose: bool = false,
};

fn doSomething(options: Options) !void {
    // Implementation
}

// Usage
try doSomething(.{
    .timeout_ms = 5000,
    .verbose = true,
});
```

## Common Mistakes to Avoid

- Forgetting to free memory when using manual allocation
- Using pointer casting when safer alternatives exist
- Ignoring error return values
- Using global state when avoidable
- Creating unnecessary dependencies between modules
- Using platform-specific code without proper conditional compilation

## Performance Considerations

- Use `@prefetch` for performance-critical memory access
- Consider packing data for cache locality
- Use `@Vector` for SIMD operations when appropriate
- Profile before optimizing
- Be aware of allocator performance characteristics

## Contribution Workflow

1. Create a new branch for your changes
2. Make your changes and ensure they follow the guidelines
3. Run tests to ensure nothing breaks
4. Format your code with `zig fmt`
5. Push your changes and create a pull request

## Additional Resources

- [Zig Documentation](https://ziglang.org/documentation/master/)
- [Zig Standard Library](https://ziglang.org/documentation/master/std/)
- [Zig Community Wiki](https://github.com/zigtools/zls)
- [Ziglings - Learn Zig by fixing tiny broken programs](https://github.com/ratfactor/ziglings)
