const std = @import("std");

pub fn validateReader(comptime ReaderType: type) void {
    if (!@hasDecl(ReaderType, "readByte")) {
        @compileError("Reader must have readByte method");
    }

    if (!@hasDecl(ReaderType, "readAll")) {
        @compileError("Reader must have readAll method");
    }
}
