const std = @import("std");

fn wrapStyle(allocator: std.mem.Allocator, op: u8, cl: u8) ![2][]u8 {
    const open = try std.fmt.allocPrint(allocator, "\u{001B}[{}m", .{op});
    errdefer allocator.free(open);
    const close = std.fmt.allocPrint(allocator, "\u{001B}[{}m", .{cl});
    return [2][]u8{ open, close };
}

fn writeAnsi16m(
    writer: anytype,
    bg: bool,
    r: u8,
    g: u8,
    b: u8,
) !void {
    const bg_int: u8 = if (bg) 48 else 38;
    try writer.print(
        "\u{001B}[{};2;{};{};{}m",
        .{ bg_int, r, g, b },
    );
}

const ANSI16M_CLOSE = "\u{001B}[39m";

pub const Color = struct {
    bg: bool,
    r: u8,
    g: u8,
    b: u8,
};

pub const Style = struct {
    op: u8,
    cl: u8,
};

const ColorStyle = union(enum) {
    Color: Color,
    Style: Style,
};

pub const Farbe = struct {
    pub usingnamespace FarbeMixin(Farbe);

    stack: std.ArrayList(ColorStyle),

    pub fn init(allocator: std.mem.Allocator) Farbe {
        return .{
            .stack = std.ArrayList(ColorStyle).init(allocator),
        };
    }

    pub fn deinit(f: *Farbe) void {
        f.stack.deinit();
        f.* = undefined;
    }

    fn items(f: Farbe) []const ColorStyle {
        return f.stack.items;
    }

    pub fn pop(f: *Farbe) !void {
        _ = f.stack.pop();
    }

    pub fn push(f: *Farbe, cs: ColorStyle) !void {
        try f.stack.append(cs);
    }
};

pub fn BufferedFarbe(comptime size: comptime_int) type {
    return struct {
        const Self = @This();
        pub usingnamespace FarbeMixin(Self);

        buffer: [size]ColorStyle = undefined,
        index: usize = 0,

        pub fn init() Self {
            return .{};
        }

        fn items(f: Self) []const ColorStyle {
            return f.buffer[0..f.index];
        }

        pub fn pop(f: *Self) !void {
            f.index -= 1;
        }

        pub fn push(f: *Self, cs: ColorStyle) !void {
            f.buffer[f.index] = cs;
            f.index += 1;
        }
    };
}

fn FarbeMixin(comptime Self: type) type {
    return struct {
        pub fn bgRgb(f: *Self, r: u8, g: u8, b: u8) !void {
            const color: Color = .{ .bg = true, .r = r, .g = g, .b = b };
            try f.push(.{ .Color = color });
        }

        pub fn fgRgb(f: *Self, r: u8, g: u8, b: u8) !void {
            const color: Color = .{ .bg = false, .r = r, .g = g, .b = b };
            try f.push(.{ .Color = color });
        }

        pub fn reset(f: *Self) !void {
            try f.push(.{ .Style = .{ .op = 0, .cl = 0 } });
        }

        pub fn bold(f: *Self) !void {
            try f.push(.{ .Style = .{ .op = 1, .cl = 22 } });
        }

        pub fn dim(f: *Self) !void {
            try f.push(.{ .Style = .{ .op = 2, .cl = 22 } });
        }

        pub fn italic(f: *Self) !void {
            try f.push(.{ .Style = .{ .op = 3, .cl = 23 } });
        }

        pub fn underlined(f: *Self) !void {
            try f.push(.{ .Style = .{ .op = 4, .cl = 24 } });
        }

        pub fn inverse(f: *Self) !void {
            try f.push(.{ .Style = .{ .op = 7, .cl = 27 } });
        }

        pub fn hidden(f: *Self) !void {
            try f.push(.{ .Style = .{ .op = 8, .cl = 28 } });
        }

        pub fn strikethrough(f: *Self) !void {
            try f.push(.{ .Style = .{ .op = 9, .cl = 29 } });
        }

        pub fn overline(f: *Self) !void {
            try f.push(.{ .Style = .{ .op = 53, .cl = 55 } });
        }

        pub fn writeOpen(f: Self, writer: anytype) !void {
            const items = f.items();
            for (items) |cs| {
                switch (cs) {
                    .Color => |c| try writeAnsi16m(writer, c.bg, c.r, c.g, c.b),
                    .Style => |s| try writer.print("\u{001B}[{}m", .{s.op}),
                }
            }
        }

        pub fn writeClose(f: Self, writer: anytype) !void {
            const items = f.items();
            const end = items.len;
            for (1..end) |i| {
                const cs = items[end - i];
                switch (cs) {
                    .Color => |c| try writer.writeAll(
                        if (c.bg) "\u{001B}[49m" else "\u{001B}[39m",
                    ),
                    .Style => |s| try writer.print("\u{001B}[{}m", .{s.cl}),
                }
            }
        }

        /// Caller owns memory.
        pub fn open(f: Self, allocator: std.mem.Allocator) ![]const u8 {
            var buf = std.ArrayList(u8).init(allocator);
            var writer = buf.writer();
            try f.writeOpen(writer);
            return buf.toOwnedSlice();
        }

        /// Caller owns memory.
        pub fn close(f: Self, allocator: std.mem.Allocator) ![]const u8 {
            var buf = std.ArrayList(u8).init(allocator);
            var writer = buf.writer();
            try f.writeclose(writer);
            return buf.toOwnedSlice();
        }

        // Writes the formatted text using the current colour and style
        // configuration.
        pub fn write(
            f: Self,
            writer: anytype,
            comptime fmt: []const u8,
            args: anytype,
        ) !void {
            try f.writeOpen(writer);
            try writer.print(fmt, args);
            try f.writeClose(writer);
        }
    };
}

test "compile time colors" {
    comptime var color = BufferedFarbe(10).init();
    try color.bold();
}
