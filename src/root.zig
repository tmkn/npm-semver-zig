const std = @import("std");
const Io = std.Io;

pub const Lexer = @import("lexer.zig").Lexer;
pub const Token = @import("lexer.zig").Token;

test {
    _ = @import("lexer.zig");
}
