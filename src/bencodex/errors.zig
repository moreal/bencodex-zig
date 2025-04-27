const std = @import("std");

pub const Error = error{
    UnexpectedEof,
    InvalidFormat,
    MalformedInteger,
    MalformedBinary,
    MalformedDictionary,
    InvalidUtf8,
    Unsupported,
    OutOfMemory,
    UnknownError,
};
