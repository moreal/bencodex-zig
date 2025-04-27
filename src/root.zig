//! By convention, root.zig is the root source file when making a library. If
//! you are making an executable, the convention is to delete this file and
//! start with main.zig instead.
const std = @import("std");

// Bencodex 모듈 내보내기
pub const bencodex = struct {
    pub const types = @import("bencodex/types.zig");
    pub const encode = @import("bencodex/encode.zig");
    pub const decode = @import("bencodex/decode.zig");
    pub const errors = @import("bencodex/errors.zig");
};

// Export all submodules
pub usingnamespace bencodex;
