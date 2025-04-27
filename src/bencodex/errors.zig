const std = @import("std");

pub const DecodeError = error{
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

pub const EncodeError = error{
    UnknownError,
};
