const std = @import("std");
const Io = std.Io;

const npm_semver_zig = @import("npm_semver_zig");
const Lexer = npm_semver_zig.Lexer;
const Token = npm_semver_zig.Token;
const Parser = npm_semver_zig.Parser;
const Node = npm_semver_zig.Node;
const Comparator = npm_semver_zig.Comparator;

pub fn main() !void {
    // const input = "1.2.3-alpha+build.1||2.0.0";
    // const input = ">=1.0.0 <2.0.0 || >=3.0.0";
    const input = "1.2.3-rc.1+sha.abc";
    var myLexer = Lexer.init(input);
    var buffer: [100]Token = undefined;

    const tokens = myLexer.tokenize(&buffer) catch {
        std.log.debug("Buffer too small", .{});

        return;
    };

    // std.log.debug("Input: \"{s}\"", .{myLexer.input});
    // for (tokens, 0..) |token, i| {
    //     std.log.debug("[{d: >2}] {f}", .{ i, token });
    // }

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const allocator = arena.allocator();
    var parser = Parser.init(allocator, tokens);

    const ast = try parser.parse();

    std.log.debug(" Input: {s}", .{input});
    std.log.debug("Result: {f}", .{ast.*});
}
