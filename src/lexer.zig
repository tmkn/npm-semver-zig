const std = @import("std");

pub const UnknownInput = struct {
    c: u8,
    pos: usize,
};

pub const Comparator = enum {
    eq,
    gt,
    lt,
    gte,
    lte,
};

pub const Token = union(enum) {
    text: []const u8,
    number: []const u8,
    dot,
    tilde,
    caret,
    wildcard,
    dash,
    plus,
    whitespace: []const u8,
    logical_and, // TODO: remove, its not needed
    logical_or,
    comparator: Comparator,
    eof,
    unknown: UnknownInput,

    pub fn format(self: @This(), writer: *std.Io.Writer) std.Io.Writer.Error!void {
        try writer.print("{s}", .{@tagName(self)});

        switch (self) {
            .text => |n| try writer.print("(\"{s}\")", .{n}),
            .number => |n| try writer.print("(\"{s}\")", .{n}),
            .whitespace => |n| try writer.print("(\"{any}\")", .{n}),
            .comparator => |n| {
                switch (n) {
                    Comparator.eq => try writer.print("(eq)", .{}),
                    Comparator.gt => try writer.print("(gt)", .{}),
                    Comparator.gte => try writer.print("(gte)", .{}),
                    Comparator.lt => try writer.print("(lt)", .{}),
                    Comparator.lte => try writer.print("(lte)", .{}),
                }
            },
            .unknown => |u| try writer.print("(char: '{c}', pos: {})", .{ u.c, u.pos }),
            else => {},
        }
    }
};

pub const Lexer = struct {
    input: []const u8,
    current_pos: usize = 0,

    pub fn init(input: []const u8) Lexer {
        return Lexer{ .input = input };
    }

    pub fn tokenize(self: *Lexer, buffer: []Token) ![]Token {
        var token_size: usize = 0;

        self.current_pos = 0;

        while (self.current_pos < self.input.len) {
            const c = self.input[self.current_pos];

            const token: Token = switch (c) {
                ' ', '\t' => blk: {
                    const data = self.consumeWhitespace(self.input[self.current_pos..]);

                    self.current_pos += data.len;

                    break :blk Token{ .whitespace = data };
                },
                '.' => blk: {
                    self.current_pos += 1;

                    break :blk Token.dot;
                },
                '^' => blk: {
                    self.current_pos += 1;

                    break :blk Token.caret;
                },
                '~' => blk: {
                    self.current_pos += 1;

                    break :blk Token.tilde;
                },
                '*' => blk: {
                    self.current_pos += 1;

                    break :blk Token.wildcard;
                },
                '-' => blk: {
                    self.current_pos += 1;

                    break :blk Token.dash;
                },
                '+' => blk: {
                    self.current_pos += 1;

                    break :blk Token.plus;
                },
                '=' => blk: {
                    self.current_pos += 1;

                    break :blk .{ .comparator = Comparator.eq };
                },
                '&' => blk: {
                    // TODO: remove, && is invalid syntax
                    if (self.peek() == '&') {
                        self.current_pos += 2;

                        break :blk Token.logical_and;
                    } else {
                        self.current_pos += 1;

                        break :blk Token{ .unknown = .{ .c = c, .pos = self.current_pos - 1 } };
                    }
                },
                '|' => blk: {
                    if (self.peek() == '|') {
                        self.current_pos += 2;

                        break :blk Token.logical_or;
                    } else {
                        self.current_pos += 1;

                        break :blk Token{ .unknown = .{ .c = c, .pos = self.current_pos - 1 } };
                    }
                },
                '>' => blk: {
                    if (self.peek() == '=') {
                        self.current_pos += 2;

                        break :blk Token{ .comparator = Comparator.gte };
                    } else {
                        self.current_pos += 1;

                        break :blk Token{ .comparator = Comparator.gt };
                    }
                },
                '<' => blk: {
                    if (self.peek() == '=') {
                        self.current_pos += 2;

                        break :blk Token{ .comparator = Comparator.lte };
                    } else {
                        self.current_pos += 1;

                        break :blk Token{ .comparator = Comparator.lt };
                    }
                },
                'A'...'Z', 'a'...'z' => blk: {
                    const data = self.consumeText(self.input[self.current_pos..]);

                    self.current_pos += data.len;

                    break :blk Token{ .text = data };
                },
                '0'...'9' => blk: {
                    const data = self.consumeNumber(self.input[self.current_pos..]);

                    self.current_pos += data.len;

                    break :blk Token{ .number = data };
                },
                else => blk: {
                    self.current_pos += 1;

                    break :blk Token{ .unknown = .{ .c = c, .pos = self.current_pos - 1 } };
                },
            };

            if (token_size < buffer.len) {
                buffer[token_size] = token;
                token_size += 1;
            } else {
                return error.BufferTooSmall;
            }
        }

        // add eof token
        if (token_size < buffer.len) {
            buffer[token_size] = Token.eof;
            token_size += 1;
        }

        return buffer[0..token_size];
    }

    fn peek(self: *Lexer) ?u8 {
        const next = self.current_pos + 1;

        if (next >= self.input.len) {
            return null;
        }

        return self.input[next];
    }

    fn consume(_: Lexer, input: []const u8, shouldConsume: fn (c: u8) bool) []const u8 {
        var i: usize = 0;

        while (i < input.len) {
            const c = input[i];

            if (shouldConsume(c)) {
                i += 1;
            } else {
                break;
            }
        }

        return input[0..i];
    }

    fn consumeNumber(self: Lexer, input: []const u8) []const u8 {
        const output = self.consume(input, isNumber);

        return output;
    }

    fn consumeText(self: Lexer, input: []const u8) []const u8 {
        const output = self.consume(input, isText);

        return output;
    }

    fn consumeWhitespace(self: Lexer, input: []const u8) []const u8 {
        const output = self.consume(input, isWhitespace);

        return output;
    }
};

fn isNumber(c: u8) bool {
    return switch (c) {
        '0'...'9' => true,
        else => false,
    };
}

fn isText(c: u8) bool {
    return switch (c) {
        'A'...'Z',
        'a'...'z',
        ':',
        '/',
        '-',
        => true,
        else => false,
    };
}

fn isWhitespace(c: u8) bool {
    return switch (c) {
        ' ',
        '\t',
        => true,
        else => false,
    };
}

test "lexer tests" {
    const TestCase = struct {
        input: []const u8,
        expected: []const Token,
    };

    const cases = [_]TestCase{
        // Basic Semantic Versions
        .{
            .input = "1.2.3",
            .expected = &[_]Token{
                .{ .number = "1" },
                .dot,
                .{ .number = "2" },
                .dot,
                .{ .number = "3" },
                .eof,
            },
        },
        .{
            .input = "v1.2.3",
            .expected = &[_]Token{
                .{ .text = "v" },
                .{ .number = "1" },
                .dot,
                .{ .number = "2" },
                .dot,
                .{ .number = "3" },
                .eof,
            },
        },
        .{
            .input = "10.20.30",
            .expected = &[_]Token{
                .{ .number = "10" },
                .dot,
                .{ .number = "20" },
                .dot,
                .{ .number = "30" },
                .eof,
            },
        },
        .{
            .input = "1",
            .expected = &[_]Token{
                .{ .number = "1" },
                .eof,
            },
        },
        .{
            .input = "1.2",
            .expected = &[_]Token{
                .{ .number = "1" },
                .dot,
                .{ .number = "2" },
                .eof,
            },
        },

        // Equal
        .{
            .input = "=",
            .expected = &[_]Token{
                .{ .comparator = Comparator.eq },
                .eof,
            },
        },
        .{
            .input = "=1.2.3",
            .expected = &[_]Token{
                .{ .comparator = Comparator.eq },
                .{ .number = "1" },
                .dot,
                .{ .number = "2" },
                .dot,
                .{ .number = "3" },
                .eof,
            },
        },
        .{
            .input = "= 1.2.3",
            .expected = &[_]Token{
                .{ .comparator = Comparator.eq },
                .{ .whitespace = " " },
                .{ .number = "1" },
                .dot,
                .{ .number = "2" },
                .dot,
                .{ .number = "3" },
                .eof,
            },
        },
        .{
            .input = "=1.2.3 || =2.0.0",
            .expected = &[_]Token{
                .{ .comparator = Comparator.eq },
                .{ .number = "1" },
                .dot,
                .{ .number = "2" },
                .dot,
                .{ .number = "3" },
                .{ .whitespace = " " },
                .logical_or,
                .{ .whitespace = " " },
                .{ .comparator = Comparator.eq },
                .{ .number = "2" },
                .dot,
                .{ .number = "0" },
                .dot,
                .{ .number = "0" },
                .eof,
            },
        },

        // Range Operators
        .{
            .input = "^1.2.3",
            .expected = &[_]Token{
                .caret,
                .{ .number = "1" },
                .dot,
                .{ .number = "2" },
                .dot,
                .{ .number = "3" },
                .eof,
            },
        },
        .{
            .input = "~1.2.3",
            .expected = &[_]Token{
                .tilde,
                .{ .number = "1" },
                .dot,
                .{ .number = "2" },
                .dot,
                .{ .number = "3" },
                .eof,
            },
        },
        .{
            .input = ">=1.2.3",
            .expected = &[_]Token{
                .{ .comparator = Comparator.gte },
                .{ .number = "1" },
                .dot,
                .{ .number = "2" },
                .dot,
                .{ .number = "3" },
                .eof,
            },
        },
        .{
            .input = "<=1.2.3",
            .expected = &[_]Token{
                .{ .comparator = Comparator.lte },
                .{ .number = "1" },
                .dot,
                .{ .number = "2" },
                .dot,
                .{ .number = "3" },
                .eof,
            },
        },
        .{
            .input = ">1.2.3",
            .expected = &[_]Token{
                .{ .comparator = Comparator.gt },
                .{ .number = "1" },
                .dot,
                .{ .number = "2" },
                .dot,
                .{ .number = "3" },
                .eof,
            },
        },
        .{
            .input = "<1.2.3",
            .expected = &[_]Token{
                .{ .comparator = Comparator.lt },
                .{ .number = "1" },
                .dot,
                .{ .number = "2" },
                .dot,
                .{ .number = "3" },
                .eof,
            },
        },

        // Logical OR
        .{
            .input = "||",
            .expected = &[_]Token{ .logical_or, .eof },
        },
        .{
            .input = "1.2.3 || 2.0.0",
            .expected = &[_]Token{
                .{ .number = "1" },
                .dot,
                .{ .number = "2" },
                .dot,
                .{ .number = "3" },
                .{ .whitespace = " " },
                .logical_or,
                .{ .whitespace = " " },
                .{ .number = "2" },
                .dot,
                .{ .number = "0" },
                .dot,
                .{ .number = "0" },
                .eof,
            },
        },

        // Logical AND
        .{
            .input = ">=1.2.3 <2.0.0",
            .expected = &[_]Token{
                .{ .comparator = Comparator.gte },
                .{ .number = "1" },
                .dot,
                .{ .number = "2" },
                .dot,
                .{ .number = "3" },
                .{ .whitespace = " " },
                .{ .comparator = Comparator.lt },
                .{ .number = "2" },
                .dot,
                .{ .number = "0" },
                .dot,
                .{ .number = "0" },
                .eof,
            },
        },
        .{
            .input = ">=1.2.3 <2.0.0",
            .expected = &[_]Token{
                .{ .comparator = Comparator.gte },
                .{ .number = "1" },
                .dot,
                .{ .number = "2" },
                .dot,
                .{ .number = "3" },
                .{ .whitespace = " " },
                .{ .comparator = Comparator.lt },
                .{ .number = "2" },
                .dot,
                .{ .number = "0" },
                .dot,
                .{ .number = "0" },

                .eof,
            },
        },
        .{
            .input = ">=1.2.3-0 <2.0.0",
            .expected = &[_]Token{
                .{ .comparator = Comparator.gte },
                .{ .number = "1" },
                .dot,
                .{ .number = "2" },
                .dot,
                .{ .number = "3" },
                .dash,
                .{ .number = "0" },
                .{ .whitespace = " " },
                .{ .comparator = Comparator.lt },
                .{ .number = "2" },
                .dot,
                .{ .number = "0" },
                .dot,
                .{ .number = "0" },

                .eof,
            },
        },
        .{
            .input = "1.x >=1.2.0",
            .expected = &[_]Token{
                .{ .number = "1" },
                .dot,
                .{ .text = "x" },
                .{ .whitespace = " " },
                .{ .comparator = Comparator.gte },
                .{ .number = "1" },
                .dot,
                .{ .number = "2" },
                .dot,
                .{ .number = "0" },

                .eof,
            },
        },
        .{
            .input = "~1.2 >=1.2.3",
            .expected = &[_]Token{
                .tilde,
                .{ .number = "1" },
                .dot,
                .{ .number = "2" },
                .{ .whitespace = " " },
                .{ .comparator = Comparator.gte },
                .{ .number = "1" },
                .dot,
                .{ .number = "2" },
                .dot,
                .{ .number = "3" },
                .eof,
            },
        },
        .{
            .input = ">=1.0.0 <2.0.0 >=1.5.0",
            .expected = &[_]Token{
                .{ .comparator = Comparator.gte },
                .{ .number = "1" },
                .dot,
                .{ .number = "0" },
                .dot,
                .{ .number = "0" },
                .{ .whitespace = " " },
                .{ .comparator = Comparator.lt },
                .{ .number = "2" },
                .dot,
                .{ .number = "0" },
                .dot,
                .{ .number = "0" },
                .{ .whitespace = " " },
                .{ .comparator = Comparator.gte },
                .{ .number = "1" },
                .dot,
                .{ .number = "5" },
                .dot,
                .{ .number = "0" },
                .eof,
            },
        },
        .{
            .input = ">=1.0.0 <2.0.0 || >=3.0.0",
            .expected = &[_]Token{
                .{ .comparator = Comparator.gte },
                .{ .number = "1" },
                .dot,
                .{ .number = "0" },
                .dot,
                .{ .number = "0" },

                .{ .whitespace = " " },

                .{ .comparator = Comparator.lt },
                .{ .number = "2" },
                .dot,
                .{ .number = "0" },
                .dot,
                .{ .number = "0" },

                .{ .whitespace = " " },

                .logical_or,

                .{ .whitespace = " " },

                .{ .comparator = Comparator.gte },
                .{ .number = "3" },
                .dot,
                .{ .number = "0" },
                .dot,
                .{ .number = "0" },

                .eof,
            },
        },

        // Pre-release and Build Metadata
        .{
            .input = "1.0.0-alpha.1",
            .expected = &[_]Token{
                .{ .number = "1" },
                .dot,
                .{ .number = "0" },
                .dot,
                .{ .number = "0" },
                .dash,
                .{ .text = "alpha" },
                .dot,
                .{ .number = "1" },
                .eof,
            },
        },
        .{
            .input = "1.0.0-alpha.beta",
            .expected = &[_]Token{
                .{ .number = "1" },
                .dot,
                .{ .number = "0" },
                .dot,
                .{ .number = "0" },
                .dash,
                .{ .text = "alpha" },
                .dot,
                .{ .text = "beta" },
                .eof,
            },
        },
        .{
            .input = "1.0.0-0.3.7",
            .expected = &[_]Token{
                .{ .number = "1" },
                .dot,
                .{ .number = "0" },
                .dot,
                .{ .number = "0" },
                .dash,
                .{ .number = "0" },
                .dot,
                .{ .number = "3" },
                .dot,
                .{ .number = "7" },
                .eof,
            },
        },
        // Pre-release and Build Metadata
        .{
            .input = "1.0.0-x.7.z.92",
            .expected = &[_]Token{
                .{ .number = "1" },
                .dot,
                .{ .number = "0" },
                .dot,
                .{ .number = "0" },
                .dash,
                .{ .text = "x" },
                .dot,
                .{ .number = "7" },
                .dot,
                .{ .text = "z" },
                .dot,
                .{ .number = "92" },
                .eof,
            },
        },
        .{
            .input = "1.0.0+build.1",
            .expected = &[_]Token{
                .{ .number = "1" },
                .dot,
                .{ .number = "0" },
                .dot,
                .{ .number = "0" },
                .plus,
                .{ .text = "build" },
                .dot,
                .{ .number = "1" },
                .eof,
            },
        },
        .{
            .input = "1.2.3-beta.4+build.5678",
            .expected = &[_]Token{
                .{ .number = "1" },
                .dot,
                .{ .number = "2" },
                .dot,
                .{ .number = "3" },
                .dash,
                .{ .text = "beta" },
                .dot,
                .{ .number = "4" },
                .plus,
                .{ .text = "build" },
                .dot,
                .{ .number = "5678" },
                .eof,
            },
        },

        // Whitespace Handling
        .{
            .input = ">= 1.2.3",
            .expected = &[_]Token{
                .{ .comparator = Comparator.gte },
                .{ .whitespace = " " },
                .{ .number = "1" },
                .dot,
                .{ .number = "2" },
                .dot,
                .{ .number = "3" },
                .eof,
            },
        },
        .{
            .input = "1.2.3   ||   4.5.6",
            .expected = &[_]Token{
                .{ .number = "1" },
                .dot,
                .{ .number = "2" },
                .dot,
                .{ .number = "3" },
                .{ .whitespace = "   " },
                .logical_or,
                .{ .whitespace = "   " },
                .{ .number = "4" },
                .dot,
                .{ .number = "5" },
                .dot,
                .{ .number = "6" },
                .eof,
            },
        },
        .{
            .input = "   1.2.3   ",
            .expected = &[_]Token{
                .{ .whitespace = "   " },
                .{ .number = "1" },
                .dot,
                .{ .number = "2" },
                .dot,
                .{ .number = "3" },
                .{ .whitespace = "   " },
                .eof,
            },
        },

        // Wildcards
        .{
            .input = "x",
            .expected = &[_]Token{
                .{ .text = "x" },
                .eof,
            },
        },
        .{
            .input = "X",
            .expected = &[_]Token{
                .{ .text = "X" },
                .eof,
            },
        },
        .{
            .input = "*",
            .expected = &[_]Token{
                .wildcard,
                .eof,
            },
        },
        .{
            .input = "1.x",
            .expected = &[_]Token{
                .{ .number = "1" },
                .dot,
                .{ .text = "x" },
                .eof,
            },
        },
        .{
            .input = "1.X",
            .expected = &[_]Token{
                .{ .number = "1" },
                .dot,
                .{ .text = "X" },
                .eof,
            },
        },
        .{
            .input = "1.*",
            .expected = &[_]Token{
                .{ .number = "1" },
                .dot,
                .wildcard,
                .eof,
            },
        },
        .{
            .input = "1.x.x",
            .expected = &[_]Token{
                .{ .number = "1" },
                .dot,
                .{ .text = "x" },
                .dot,
                .{ .text = "x" },
                .eof,
            },
        },
        .{
            .input = "1.X.*",
            .expected = &[_]Token{
                .{ .number = "1" },
                .dot,
                .{ .text = "X" },
                .dot,
                .wildcard,
                .eof,
            },
        },
        .{
            .input = "x.x.x",
            .expected = &[_]Token{
                .{ .text = "x" },
                .dot,
                .{ .text = "x" },
                .dot,
                .{ .text = "x" },
                .eof,
            },
        },
        .{
            .input = "^1.x",
            .expected = &[_]Token{
                .caret,
                .{ .number = "1" },
                .dot,
                .{ .text = "x" },
                .eof,
            },
        },

        // Hypen Ranges
        .{
            .input = "1.2.3 - 2.3.4",
            .expected = &[_]Token{
                .{ .number = "1" },
                .dot,
                .{ .number = "2" },
                .dot,
                .{ .number = "3" },
                .{ .whitespace = " " },
                .dash,
                .{ .whitespace = " " },
                .{ .number = "2" },
                .dot,
                .{ .number = "3" },
                .dot,
                .{ .number = "4" },
                .eof,
            },
        },

        // Interesting Edge Cases
        .{
            .input = "^0.0.3",
            .expected = &[_]Token{
                .caret,
                .{ .number = "0" },
                .dot,
                .{ .number = "0" },
                .dot,
                .{ .number = "3" },
                .eof,
            },
        },
        .{
            .input = "0.0.0-0",
            .expected = &[_]Token{
                .{ .number = "0" },
                .dot,
                .{ .number = "0" },
                .dot,
                .{ .number = "0" },
                .dash,
                .{ .number = "0" },
                .eof,
            },
        },
        .{
            .input = ">=1.2.3-0",
            .expected = &[_]Token{
                .{ .comparator = Comparator.gte },
                .{ .number = "1" },
                .dot,
                .{ .number = "2" },
                .dot,
                .{ .number = "3" },
                .dash,
                .{ .number = "0" },
                .eof,
            },
        },

        // Url, Aliases
        .{
            .input = "git://github.com/user/project.git",
            .expected = &[_]Token{
                .{ .text = "git://github" },
                .dot,
                .{ .text = "com/user/project" },
                .dot,
                .{ .text = "git" },
                .eof,
            },
        },
        .{
            .input = "file:../local-pkg",
            .expected = &[_]Token{
                .{ .text = "file:" },
                .dot,
                .dot,
                .{ .unknown = .{ .c = '/', .pos = 7 } },
                .{ .text = "local-pkg" },
                .eof,
            },
        },
        .{
            .input = "1.0.0-alpha-beta",
            .expected = &[_]Token{
                .{ .number = "1" },
                .dot,
                .{ .number = "0" },
                .dot,
                .{ .number = "0" },
                .dash,
                .{ .text = "alpha-beta" },
                .eof,
            },
        },
        .{
            .input = "1.0.0-x-y-z",
            .expected = &[_]Token{
                .{ .number = "1" },
                .dot,
                .{ .number = "0" },
                .dot,
                .{ .number = "0" },
                .dash,
                .{ .text = "x-y-z" },
                .eof,
            },
        },
        .{
            .input = "github:user/repo#v1.0.0",
            .expected = &[_]Token{
                .{ .text = "github:user/repo" },
                .{ .unknown = .{ .c = '#', .pos = 16 } },
                .{ .text = "v" },
                .{ .number = "1" },
                .dot,
                .{ .number = "0" },
                .dot,
                .{ .number = "0" },
                .eof,
            },
        },
        .{
            .input = "npm:lodash@^3.0.0",
            .expected = &[_]Token{
                .{ .text = "npm:lodash" },
                .{ .unknown = .{ .c = '@', .pos = 10 } },
                .caret,
                .{ .number = "3" },
                .dot,
                .{ .number = "0" },
                .dot,
                .{ .number = "0" },
                .eof,
            },
        },
        .{
            .input = "npm:@org/pkg@1.2.3",
            .expected = &[_]Token{
                .{ .text = "npm:" },
                .{ .unknown = .{ .c = '@', .pos = 4 } },
                .{ .text = "org/pkg" },
                .{ .unknown = .{ .c = '@', .pos = 12 } },
                .{ .number = "1" },
                .dot,
                .{ .number = "2" },
                .dot,
                .{ .number = "3" },
                .eof,
            },
        },
    };

    var buffer: [100]Token = undefined;

    for (cases) |case| {
        var lexer = Lexer.init(case.input);

        const actual_tokens = try lexer.tokenize(&buffer);

        std.testing.expectEqualDeep(case.expected, actual_tokens) catch |err| {
            std.debug.print("\n=== TEST FAILED ===\n", .{});
            std.debug.print("Input: '{s}'\n", .{case.input});

            printSideBySide(case.expected, actual_tokens);

            return err;
        };
    }
}

fn printSideBySide(expected: []const Token, actual: []const Token) void {
    var max_left_width: usize = 16;

    for (expected) |tok| {
        var temp_buf: [128]u8 = undefined;
        if (std.fmt.bufPrint(&temp_buf, "{}", .{tok})) |str| {
            if (str.len > max_left_width) max_left_width = str.len;
        } else |_| {}
    }

    const left_col_total = max_left_width + 5;
    const spaces = " " ** 128;
    const dashes = "-" ** 128;

    std.debug.print("\n--- EXPECTED ---{s} | --- ACTUAL ---\n", .{
        spaces[0 .. left_col_total - 16],
    });
    std.debug.print("{s}-+-{s}\n", .{ dashes[0..left_col_total], dashes[0..left_col_total] });

    const max_len = @max(expected.len, actual.len);

    for (0..max_len) |i| {
        var exp_buf: [128]u8 = undefined;
        var act_buf: [128]u8 = undefined;

        const act_str = if (i < actual.len)
            std.fmt.bufPrint(&act_buf, "{f}", .{actual[i]}) catch "error"
        else
            "---";

        const exp_str = if (i < expected.len)
            std.fmt.bufPrint(&exp_buf, "{f}", .{expected[i]}) catch "error"
        else
            "---";

        const padding = max_left_width - exp_str.len;

        const is_match = std.mem.eql(u8, exp_str, act_str);

        const color_start = if (is_match) "" else "\x1b[31m";
        const color_reset = if (is_match) "" else "\x1b[0m";

        std.debug.print("{s}[{d: >2}] {s}{s} | [{d: >2}] {s}{s}\n", .{ color_start, i, exp_str, spaces[0..padding], i, act_str, color_reset });
    }
    std.debug.print("\n", .{});
}
