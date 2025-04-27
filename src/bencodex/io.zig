const std = @import("std");

/// Reader 타입이 필요한 인터페이스를 갖추고 있는지 컴파일 타임에 검증합니다.
pub fn validateReader(comptime ReaderType: type) void {
    // Reader가 readByte() 메서드를 가져야 합니다
    if (!@hasDecl(ReaderType, "readByte")) {
        @compileError("Reader must have readByte method");
    }

    // Reader가 readAll() 메서드를 가져야 합니다
    if (!@hasDecl(ReaderType, "readAll")) {
        @compileError("Reader must have readAll method");
    }
}
