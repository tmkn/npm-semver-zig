const std = @import("std");
const Io = std.Io;

const npm_semver_zig = @import("npm_semver_zig");

pub fn main() void {
    var myLexer = npm_semver_zig.Lexer.init("1.2.3-alpha+build.1||2.0.0");
    var buffer: [100]npm_semver_zig.Token = undefined;

    const tokens = myLexer.tokenize(&buffer) catch {
        std.log.debug("Buffer too small", .{});

        return;
    };

    std.log.debug("Input: \"{s}\"", .{myLexer.input});
    for (tokens, 0..) |token, i| {
        std.log.debug("[{d: >2}] {f}", .{ i, token });
    }
}
