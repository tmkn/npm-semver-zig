const std = @import("std");
const Allocator = std.mem.Allocator;

const lexer = @import("lexer.zig");
const Comparator = lexer.Comparator;
const Token = lexer.Token;

pub const Part = union(enum) {
    number: u32,
    wildcard,

    pub fn format(self: @This(), writer: *std.Io.Writer) std.Io.Writer.Error!void {
        switch (self) {
            .number => |n| try writer.print("{d}", .{n}),
            .wildcard => try writer.print("*", .{}),
        }
    }
};

pub const PrereleaseIdentifier = union(enum) {
    numeric: u32,
    text: []const u8,

    pub fn format(self: @This(), writer: *std.Io.Writer) std.Io.Writer.Error!void {
        switch (self) {
            .numeric => |val| {
                try writer.print("{d}", .{val});
            },
            .text => |val| {
                try writer.print("{s}", .{val});
            },
        }
    }
};

// TODO: use std.math.order for sort
pub const Version = struct {
    major: Part,
    minor: ?Part = null,
    patch: ?Part = null,

    prerelease: ?[]const PrereleaseIdentifier = null,
    metadata: ?[]const []const u8 = null,

    pub fn format(self: @This(), writer: *std.Io.Writer) std.Io.Writer.Error!void {
        try writer.print("{f}", .{self.major});

        if (self.minor) |m| {
            try writer.print(".{f}", .{m});
        } else {
            try writer.print(".*", .{});
        }

        if (self.patch) |p| {
            try writer.print(".{f}", .{p});
        } else {
            try writer.print(".*", .{});
        }

        if (self.prerelease != null and self.prerelease.?.len > 0) {
            try writer.writeByte('-');

            for (self.prerelease.?, 0..) |val, index| {
                if (index != 0) {
                    try writer.writeByte('.');
                }

                try writer.print("{f}", .{val});
            }
        }

        if (self.metadata != null and self.metadata.?.len > 0) {
            try writer.writeByte('+');

            for (self.metadata.?, 0..) |val, index| {
                if (index != 0) {
                    try writer.writeByte('.');
                }

                try writer.print("{s}", .{val});
            }
        }
    }
};

pub const ComparatorExpression = struct {
    op: Comparator,
    version: Version,

    pub fn format(self: @This(), writer: *std.Io.Writer) std.Io.Writer.Error!void {
        // Prints like: (eq 1.2.3) or (gt 2.0.*)
        try writer.print("({s} {f})", .{ @tagName(self.op), self.version });
    }
};

pub const BinaryOp = enum {
    logical_and,
    logical_or,
};

pub const Node = union(enum) {
    comparator: ComparatorExpression,
    binary: BinaryExpression,

    pub fn format(self: @This(), writer: *std.Io.Writer) std.Io.Writer.Error!void {
        switch (self) {
            .comparator => |c| try writer.print("{f}", .{c}),
            .binary => |b| try writer.print("{f}", .{b}),
        }
    }
};

pub const BinaryExpression = struct {
    op: BinaryOp,
    left: *const Node,
    right: *const Node,

    pub fn format(self: @This(), writer: *std.Io.Writer) std.Io.Writer.Error!void {
        // Prints like: (logical_or (eq 1.2.3) (eq 2.0.0))
        try writer.print("({s} {f} {f})", .{ @tagName(self.op), self.left.*, self.right.* });
    }
};

pub const Parser = struct {
    allocator: Allocator,
    tokens: []const Token,
    current: usize = 0,

    pub fn init(allocator: Allocator, tokens: []const Token) Parser {
        return .{
            .allocator = allocator,
            .tokens = tokens,
        };
    }

    fn peek(self: *const Parser) Token {
        return self.tokens[self.current];
    }

    fn advance(self: *Parser) void {
        if (self.current < self.tokens.len)
            self.current += 1;
    }

    fn match(self: *Parser, tag: std.meta.Tag(Token)) bool {
        if (std.meta.activeTag(self.peek()) == tag) {
            self.advance();
            return true;
        }

        return false;
    }

    fn skipWhitespace(self: *Parser) void {
        while (self.match(.whitespace)) {}
    }

    fn consumeUntil(self: *Parser, stopTag: std.meta.Tag(Token)) []const Token {
        const start = self.current;

        while ((std.meta.activeTag(self.peek()) != stopTag) and (std.meta.activeTag(self.peek()) != .eof)) {
            self.advance();
        }

        return self.tokens[start..self.current];
    }

    pub fn parse(self: *Parser) !*Node {
        var ptr = try self.allocator.create(Node);
        const version = try self.parseOr();

        ptr = version;

        return ptr;
    }

    pub fn parseOr(self: *Parser) !*Node {
        var ptr = try self.allocator.create(Node);

        self.skipWhitespace();

        const left = try self.parseAnd();

        self.skipWhitespace();

        if (self.match(.logical_or)) {
            const right = try self.parseOr();

            ptr.* = .{
                .binary = .{
                    .op = .logical_or,
                    .left = left,
                    .right = right,
                },
            };
        } else {
            ptr = left;
        }

        return ptr;
    }

    pub fn parseAnd(self: *Parser) !*Node {
        var ptr = try self.allocator.create(Node);

        self.skipWhitespace();

        const left = try self.parseVersion();

        // Whitespace here might be an implicit AND separator, start of a range or just formatting padding
        self.skipWhitespace();

        // Determine which it is
        switch (self.peek()) {
            // Implicit AND
            .number, .wildcard, .comparator => {
                const right = try self.parseVersion();

                ptr.* = .{
                    .binary = .{
                        .op = .logical_and,
                        .left = left,
                        .right = right,
                    },
                };
            },
            // Range
            .dash => {
                self.advance();
                self.skipWhitespace();

                const right = try self.parseVersion();

                // TODO: convert to range

                ptr.* = .{
                    .binary = .{
                        .op = .logical_and,
                        .left = left,
                        .right = right,
                    },
                };
            },
            // just padding
            else => {
                ptr = left;
            },
        }

        return ptr;
    }

    pub fn parsePart(self: *Parser) !Part {
        switch (self.peek()) {
            .number => |txt| {
                self.advance();

                return .{
                    .number = try std.fmt.parseInt(u32, txt, 10),
                };
            },
            .wildcard => {
                self.advance();

                return .wildcard;
            },
            else => return error.ExpectedVersionPart,
        }
    }

    pub fn parsePrerelease(self: *Parser) !?[]const PrereleaseIdentifier {
        if (self.peek() == .dash) {
            self.advance();

            const prereleaseTokens = self.consumeUntil(.plus);

            var list: std.ArrayList(PrereleaseIdentifier) = .empty;
            errdefer list.deinit(self.allocator);

            for (prereleaseTokens) |token| {
                switch (token) {
                    .text => |text| {
                        try list.append(self.allocator, .{ .text = text });
                    },
                    .number => |number| {
                        if (number[0] == '0') {
                            return error.InvalidPrereleaseNumber;
                        }

                        const value = try std.fmt.parseInt(u16, number, 10);

                        try list.append(self.allocator, .{ .numeric = value });
                    },
                    .dot => continue,
                    // unexpected token, should error instead?
                    else => return null,
                }
            }

            if (list.items.len > 0) {
                return try list.toOwnedSlice(self.allocator);
            } else {
                return null;
            }
        }

        return null;
    }

    pub fn parseMetadata(self: *Parser) !?[]const []const u8 {
        if (self.peek() == .plus) {
            self.advance();

            const metadataTokens = self.consumeUntil(.whitespace);

            var list: std.ArrayList([]const u8) = .empty;
            errdefer list.deinit(self.allocator);

            for (metadataTokens) |token| {
                switch (token) {
                    .text => |text| {
                        try list.append(self.allocator, text);
                    },
                    .number => |number| {
                        try list.append(self.allocator, number);
                    },
                    .dot => continue,
                    else => return null,
                }
            }

            if (list.items.len > 0) {
                return try list.toOwnedSlice(self.allocator);
            } else {
                return null;
            }
        }

        return null;
    }

    pub fn parseVersion(self: *Parser) !*Node {
        const node = try self.allocator.create(Node);
        const comp = self.parseComparator() orelse .eq;
        const major = try self.parsePart();

        if (!self.match(.dot)) {
            node.* = .{
                .comparator = .{
                    .op = comp,
                    .version = .{
                        .major = major,
                        .minor = .wildcard,
                        .patch = .wildcard,
                    },
                },
            };

            return node;
        }

        const minor = try self.parsePart();

        if (!self.match(.dot)) {
            node.* = .{
                .comparator = .{
                    .op = comp,
                    .version = .{
                        .major = major,
                        .minor = minor,
                        .patch = .wildcard,
                    },
                },
            };

            return node;
        }

        const patch = try self.parsePart();

        node.* = .{
            .comparator = .{
                .op = comp,
                .version = .{
                    .major = major,
                    .minor = minor,
                    .patch = patch,

                    // prerelease & metadata can only come after patch version
                    .prerelease = try self.parsePrerelease(),
                    .metadata = try self.parseMetadata(),
                },
            },
        };

        return node;
    }

    pub fn parseComparator(self: *Parser) ?Comparator {
        switch (self.peek()) {
            .comparator => |comp| {
                self.advance();

                return comp;
            },
            else => return null,
        }
    }
};

test "parser tests" {
    const Testcase = struct {
        input: []const Token,
        output: *const Node,
    };

    const cases = [_]Testcase{
        // *
        .{
            .input = &[_]Token{
                .wildcard,
                .eof,
            },
            .output = &Node{
                .comparator = .{
                    .op = Comparator.eq,
                    .version = .{
                        .major = Part.wildcard,
                        .minor = Part.wildcard,
                        .patch = Part.wildcard,
                    },
                },
            },
        },

        // 1
        .{
            .input = &[_]Token{
                .{ .number = "1" },
                .eof,
            },
            .output = &Node{
                .comparator = .{
                    .op = Comparator.eq,
                    .version = .{
                        .major = Part{
                            .number = 1,
                        },
                        .minor = Part.wildcard,
                        .patch = Part.wildcard,
                    },
                },
            },
        },

        // 1.2
        .{
            .input = &[_]Token{
                .{ .number = "1" },
                .dot,
                .{ .number = "2" },
                .eof,
            },
            .output = &Node{
                .comparator = .{
                    .op = Comparator.eq,
                    .version = .{
                        .major = Part{
                            .number = 1,
                        },
                        .minor = Part{
                            .number = 2,
                        },
                        .patch = Part.wildcard,
                    },
                },
            },
        },

        // 1.2.3
        .{
            .input = &[_]Token{
                .{ .number = "1" },
                .dot,
                .{ .number = "2" },
                .dot,
                .{ .number = "3" },
                .eof,
            },
            .output = &Node{
                .comparator = .{
                    .op = Comparator.eq,
                    .version = .{
                        .major = Part{
                            .number = 1,
                        },
                        .minor = Part{
                            .number = 2,
                        },
                        .patch = Part{
                            .number = 3,
                        },
                    },
                },
            },
        },

        // 10.20.30
        .{
            .input = &[_]Token{
                .{ .number = "10" },
                .dot,
                .{ .number = "20" },
                .dot,
                .{ .number = "30" },
                .eof,
            },
            .output = &Node{
                .comparator = .{
                    .op = Comparator.eq,
                    .version = .{
                        .major = Part{
                            .number = 10,
                        },
                        .minor = Part{
                            .number = 20,
                        },
                        .patch = Part{
                            .number = 30,
                        },
                    },
                },
            },
        },

        // 1.2.3-rc.1
        .{
            .input = &[_]Token{
                .{ .number = "1" },
                .dot,
                .{ .number = "2" },
                .dot,
                .{ .number = "3" },

                .dash,

                .{ .text = "rc" },
                .dot,
                .{ .number = "1" },
                .eof,
            },

            .output = &Node{
                .comparator = .{
                    .op = Comparator.eq,
                    .version = .{
                        .major = .{ .number = 1 },
                        .minor = .{ .number = 2 },
                        .patch = .{ .number = 3 },

                        .prerelease = &.{
                            .{ .text = "rc" },
                            .{ .numeric = 1 },
                        },
                    },
                },
            },
        },

        // 1.2.3+sha.abc
        .{
            .input = &[_]Token{
                .{ .number = "1" },
                .dot,
                .{ .number = "2" },
                .dot,
                .{ .number = "3" },

                .plus,

                .{ .text = "sha" },
                .dot,
                .{ .text = "abc" },
                .eof,
            },

            .output = &Node{
                .comparator = .{
                    .op = Comparator.eq,
                    .version = .{
                        .major = .{ .number = 1 },
                        .minor = .{ .number = 2 },
                        .patch = .{ .number = 3 },

                        .metadata = &.{
                            "sha",
                            "abc",
                        },
                    },
                },
            },
        },

        // 1.2.3-rc.1+sha.abc
        .{
            .input = &[_]Token{
                .{ .number = "1" },
                .dot,
                .{ .number = "2" },
                .dot,
                .{ .number = "3" },

                .dash,

                .{ .text = "rc" },
                .dot,
                .{ .number = "1" },

                .plus,

                .{ .text = "sha" },
                .dot,
                .{ .text = "abc" },
                .eof,
            },

            .output = &Node{
                .comparator = .{
                    .op = Comparator.eq,
                    .version = .{
                        .major = .{ .number = 1 },
                        .minor = .{ .number = 2 },
                        .patch = .{ .number = 3 },

                        .prerelease = &.{
                            .{ .text = "rc" },
                            .{ .numeric = 1 },
                        },

                        .metadata = &.{
                            "sha",
                            "abc",
                        },
                    },
                },
            },
        },

        // =1.2.3
        .{
            .input = &[_]Token{
                .{ .comparator = Comparator.eq },
                .{ .number = "1" },
                .dot,
                .{ .number = "2" },
                .dot,
                .{ .number = "3" },
                .eof,
            },
            .output = &Node{
                .comparator = .{
                    .op = Comparator.eq,
                    .version = .{
                        .major = Part{
                            .number = 1,
                        },
                        .minor = Part{
                            .number = 2,
                        },
                        .patch = Part{
                            .number = 3,
                        },
                    },
                },
            },
        },

        // <1.2.3
        .{
            .input = &[_]Token{
                .{ .comparator = Comparator.lt },
                .{ .number = "1" },
                .dot,
                .{ .number = "2" },
                .dot,
                .{ .number = "3" },
                .eof,
            },
            .output = &Node{
                .comparator = .{
                    .op = Comparator.lt,
                    .version = .{
                        .major = Part{
                            .number = 1,
                        },
                        .minor = Part{
                            .number = 2,
                        },
                        .patch = Part{
                            .number = 3,
                        },
                    },
                },
            },
        },

        // <=1.2.3
        .{
            .input = &[_]Token{
                .{ .comparator = Comparator.lte },
                .{ .number = "1" },
                .dot,
                .{ .number = "2" },
                .dot,
                .{ .number = "3" },
                .eof,
            },
            .output = &Node{
                .comparator = .{
                    .op = Comparator.lte,
                    .version = .{
                        .major = Part{
                            .number = 1,
                        },
                        .minor = Part{
                            .number = 2,
                        },
                        .patch = Part{
                            .number = 3,
                        },
                    },
                },
            },
        },

        // >1.2.3
        .{
            .input = &[_]Token{
                .{ .comparator = Comparator.gt },
                .{ .number = "1" },
                .dot,
                .{ .number = "2" },
                .dot,
                .{ .number = "3" },
                .eof,
            },
            .output = &Node{
                .comparator = .{
                    .op = Comparator.gt,
                    .version = .{
                        .major = Part{
                            .number = 1,
                        },
                        .minor = Part{
                            .number = 2,
                        },
                        .patch = Part{
                            .number = 3,
                        },
                    },
                },
            },
        },

        // >=1.2.3
        .{
            .input = &[_]Token{
                .{ .comparator = Comparator.gte },
                .{ .number = "1" },
                .dot,
                .{ .number = "2" },
                .dot,
                .{ .number = "3" },
                .eof,
            },
            .output = &Node{
                .comparator = .{
                    .op = Comparator.gte,
                    .version = .{
                        .major = Part{
                            .number = 1,
                        },
                        .minor = Part{
                            .number = 2,
                        },
                        .patch = Part{
                            .number = 3,
                        },
                    },
                },
            },
        },

        // =1.2.3 || =2.0.0
        .{
            .input = &[_]Token{
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
            .output = &Node{
                .binary = .{
                    .op = .logical_or,
                    .left = &Node{
                        .comparator = .{
                            .op = Comparator.eq,
                            .version = .{
                                .major = Part{
                                    .number = 1,
                                },
                                .minor = Part{
                                    .number = 2,
                                },
                                .patch = Part{
                                    .number = 3,
                                },
                            },
                        },
                    },
                    .right = &Node{
                        .comparator = .{
                            .op = Comparator.eq,
                            .version = .{
                                .major = Part{
                                    .number = 2,
                                },
                                .minor = Part{
                                    .number = 0,
                                },
                                .patch = Part{
                                    .number = 0,
                                },
                            },
                        },
                    },
                },
            },
        },

        // >=1.0.0 <2.0.0
        .{
            .input = &[_]Token{
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

                .eof,
            },

            .output = &Node{
                .binary = .{
                    .op = .logical_and,

                    .left = &Node{
                        .comparator = .{
                            .op = .gte,
                            .version = .{
                                .major = .{ .number = 1 },
                                .minor = .{ .number = 0 },
                                .patch = .{ .number = 0 },
                            },
                        },
                    },

                    .right = &Node{
                        .comparator = .{
                            .op = .lt,
                            .version = .{
                                .major = .{ .number = 2 },
                                .minor = .{ .number = 0 },
                                .patch = .{ .number = 0 },
                            },
                        },
                    },
                },
            },
        },

        // >=1.0.0 <2.0.0 || >=3.0.0
        .{
            .input = &[_]Token{
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

            .output = &Node{
                .binary = .{
                    .op = .logical_or,

                    .left = &Node{
                        .binary = .{
                            .op = .logical_and,

                            .left = &Node{
                                .comparator = .{
                                    .op = .gte,
                                    .version = .{
                                        .major = .{ .number = 1 },
                                        .minor = .{ .number = 0 },
                                        .patch = .{ .number = 0 },
                                    },
                                },
                            },

                            .right = &Node{
                                .comparator = .{
                                    .op = .lt,
                                    .version = .{
                                        .major = .{ .number = 2 },
                                        .minor = .{ .number = 0 },
                                        .patch = .{ .number = 0 },
                                    },
                                },
                            },
                        },
                    },

                    .right = &Node{
                        .comparator = .{
                            .op = .gte,
                            .version = .{
                                .major = .{ .number = 3 },
                                .minor = .{ .number = 0 },
                                .patch = .{ .number = 0 },
                            },
                        },
                    },
                },
            },
        },

        // RANGES
        // 1.2.3 - 2.3.4
        // .{
        //     .input = &[_]Token{
        //         .{ .number = "1" },
        //         .dot,
        //         .{ .number = "2" },
        //         .dot,
        //         .{ .number = "3" },
        //         .{ .whitespace = " " },
        //         .dash,
        //         .{ .whitespace = " " },
        //         .{ .number = "2" },
        //         .dot,
        //         .{ .number = "3" },
        //         .dot,
        //         .{ .number = "4" },
        //         .eof,
        //     },
        //     .output = &Node{
        //         .binary = .{
        //             .op = .logical_and,
        //             .left = &Node{
        //                 .comparator = .{
        //                     .op = .gte,
        //                     .version = .{
        //                         .major = .{ .number = 1 },
        //                         .minor = .{ .number = 2 },
        //                         .patch = .{ .number = 3 },
        //                     },
        //                 },
        //             },
        //             .right = &Node{
        //                 .comparator = .{
        //                     .op = .lte,
        //                     .version = .{
        //                         .major = .{ .number = 2 },
        //                         .minor = .{ .number = 3 },
        //                         .patch = .{ .number = 4 },
        //                     },
        //                 },
        //             },
        //         },
        //     },
        // },

        // // 1.2 - 2.3.4  => left expands to 1.2.0
        // .{
        //     .input = &[_]Token{
        //         .{ .number = "1" },
        //         .dot,
        //         .{ .number = "2" },
        //         .{ .whitespace = " " },
        //         .dash,
        //         .{ .whitespace = " " },
        //         .{ .number = "2" },
        //         .dot,
        //         .{ .number = "3" },
        //         .dot,
        //         .{ .number = "4" },
        //         .eof,
        //     },
        //     .output = &Node{
        //         .binary = .{
        //             .op = .logical_and,
        //             .left = &Node{
        //                 .comparator = .{
        //                     .op = .gte,
        //                     .version = .{
        //                         .major = .{ .number = 1 },
        //                         .minor = .{ .number = 2 },
        //                         .patch = .{ .number = 0 },
        //                     },
        //                 },
        //             },
        //             .right = &Node{
        //                 .comparator = .{
        //                     .op = .lte,
        //                     .version = .{
        //                         .major = .{ .number = 2 },
        //                         .minor = .{ .number = 3 },
        //                         .patch = .{ .number = 4 },
        //                     },
        //                 },
        //             },
        //         },
        //     },
        // },

        // // 1.2.3 - 2.3 => right becomes <2.4.0
        // .{
        //     .input = &[_]Token{
        //         .{ .number = "1" },
        //         .dot,
        //         .{ .number = "2" },
        //         .dot,
        //         .{ .number = "3" },
        //         .{ .whitespace = " " },
        //         .dash,
        //         .{ .whitespace = " " },
        //         .{ .number = "2" },
        //         .dot,
        //         .{ .number = "3" },
        //         .eof,
        //     },
        //     .output = &Node{
        //         .binary = .{
        //             .op = .logical_and,
        //             .left = &Node{
        //                 .comparator = .{
        //                     .op = .gte,
        //                     .version = .{
        //                         .major = .{ .number = 1 },
        //                         .minor = .{ .number = 2 },
        //                         .patch = .{ .number = 3 },
        //                     },
        //                 },
        //             },
        //             .right = &Node{
        //                 .comparator = .{
        //                     .op = .lt,
        //                     .version = .{
        //                         .major = .{ .number = 2 },
        //                         .minor = .{ .number = 4 },
        //                         .patch = .{ .number = 0 },
        //                     },
        //                 },
        //             },
        //         },
        //     },
        // },

        // // 1 - 2 => 1.0.0 - <3.0.0
        // .{
        //     .input = &[_]Token{
        //         .{ .number = "1" },
        //         .{ .whitespace = " " },
        //         .dash,
        //         .{ .whitespace = " " },
        //         .{ .number = "2" },
        //         .eof,
        //     },
        //     .output = &Node{
        //         .binary = .{
        //             .op = .logical_and,
        //             .left = &Node{
        //                 .comparator = .{
        //                     .op = .gte,
        //                     .version = .{
        //                         .major = .{ .number = 1 },
        //                         .minor = .{ .number = 0 },
        //                         .patch = .{ .number = 0 },
        //                     },
        //                 },
        //             },
        //             .right = &Node{
        //                 .comparator = .{
        //                     .op = .lt,
        //                     .version = .{
        //                         .major = .{ .number = 3 },
        //                         .minor = .{ .number = 0 },
        //                         .patch = .{ .number = 0 },
        //                     },
        //                 },
        //             },
        //         },
        //     },
        // },

        // // 1.2.3-alpha.1 - 2.0.0-beta.2
        // .{
        //     .input = &[_]Token{
        //         .{ .number = "1" },
        //         .dot,
        //         .{ .number = "2" },
        //         .dot,
        //         .{ .number = "3" },
        //         .dash,
        //         .{ .text = "alpha" },
        //         .dot,
        //         .{ .number = "1" },
        //         .{ .whitespace = " " },
        //         .dash,
        //         .{ .whitespace = " " },
        //         .{ .number = "2" },
        //         .dot,
        //         .{ .number = "0" },
        //         .dot,
        //         .{ .number = "0" },
        //         .dash,
        //         .{ .text = "beta" },
        //         .dot,
        //         .{ .number = "2" },
        //         .eof,
        //     },
        //     .output = &Node{
        //         .binary = .{
        //             .op = .logical_and,
        //             .left = &Node{
        //                 .comparator = .{
        //                     .op = .gte,
        //                     .version = .{
        //                         .major = .{ .number = 1 },
        //                         .minor = .{ .number = 2 },
        //                         .patch = .{ .number = 3 },
        //                         .prerelease = &.{
        //                             .{ .text = "alpha" },
        //                             .{ .numeric = 1 },
        //                         },
        //                     },
        //                 },
        //             },
        //             .right = &Node{
        //                 .comparator = .{
        //                     .op = .lte,
        //                     .version = .{
        //                         .major = .{ .number = 2 },
        //                         .minor = .{ .number = 0 },
        //                         .patch = .{ .number = 0 },
        //                         .prerelease = &.{
        //                             .{ .text = "beta" },
        //                             .{ .numeric = 2 },
        //                         },
        //                     },
        //                 },
        //             },
        //         },
        //     },
        // },
    };

    const ErrorTestcase = struct {
        input: []const Token,
        output: anyerror,
    };

    const error_cases = [_]ErrorTestcase{
        .{
            // 1.2.3-001
            // invalid: prerelease numeric identifiers must not contain leading zeroes
            .input = &[_]Token{
                .{ .number = "1" },
                .dot,
                .{ .number = "2" },
                .dot,
                .{ .number = "3" },

                .dash,

                .{ .number = "001" },
                .eof,
            },

            .output = error.InvalidPrereleaseNumber,
        },
    };

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const allocator = arena.allocator();

    for (cases) |case| {
        var parser = Parser.init(allocator, case.input);

        try std.testing.expectEqualDeep(case.output, parser.parse());
    }

    for (error_cases) |case| {
        var parser = Parser.init(allocator, case.input);

        try std.testing.expectError(case.output, parser.parse());
    }
}
