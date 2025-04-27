const std = @import("std");

/// Bencodex 관련 오류 타입입니다.
pub const Error = error{
    /// 예기치 않은 파일 끝에 도달했을 때 발생
    UnexpectedEof,
    /// 유효하지 않은 format 형식
    InvalidFormat,
    /// 잘못된 정수 형식
    MalformedInteger,
    /// 바이너리 형식 오류
    MalformedBinary,
    /// 사전 형식 오류 (예: 정렬 규칙 위반)
    MalformedDictionary,
    /// 유효하지 않은 UTF-8 문자열
    InvalidUtf8,
    /// 지원되지 않는 작업
    Unsupported,
    /// 메모리 부족
    OutOfMemory,
    UnknownError,
};
