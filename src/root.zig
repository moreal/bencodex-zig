const std = @import("std");

pub const bencodex = struct {
    pub const types = @import("bencodex/types.zig");
    pub const encode = @import("bencodex/encode.zig");
    pub const decode = @import("bencodex/decode.zig");
    pub const errors = @import("bencodex/errors.zig");
};

pub usingnamespace bencodex;
