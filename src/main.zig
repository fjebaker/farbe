const std = @import("std");

const BACKGROUND_CODE = 48;
const FOREGROUND_CODE = 38;

fn formatAnsi(
    bg: bool,
    r: u8,
    g: u8,
    b: u8,
) [20]u8 {
    const bg_int: u8 = if (bg) BACKGROUND_CODE else FOREGROUND_CODE;
    var buf: [20]u8 = undefined;
    _ = std.fmt.bufPrint(
        &buf,
        "\u{001B}[{d:0>2};2;{d:0>3};{d:0>3};{d:0>3}m",
        .{ bg_int, r, g, b },
    ) catch unreachable;
    return buf;
}

fn writeAnsi(
    writer: anytype,
    bg: bool,
    r: u8,
    g: u8,
    b: u8,
) !void {
    try writer.writeAll(&formatAnsi(bg, r, g, b));
}

pub const Color = struct {
    bg: bool,
    r: u8,
    g: u8,
    b: u8,
};

pub const Style = struct {
    op: u8,
    cl: u8,
    pub const RESET = Style{ .op = 0, .cl = 0 };
    pub const BOLD = Style{ .op = 1, .cl = 22 };
    pub const DIM = Style{ .op = 2, .cl = 22 };
    pub const ITALIC = Style{ .op = 3, .cl = 23 };
    pub const UNDERLINED = Style{ .op = 4, .cl = 24 };
    pub const INVERSE = Style{ .op = 7, .cl = 27 };
    pub const HIDDEN = Style{ .op = 8, .cl = 28 };
    pub const STRIKETHROUGH = Style{ .op = 9, .cl = 29 };
    pub const OVERLINE = Style{ .op = 53, .cl = 55 };
};

pub const ColorStyle = union(enum) {
    Color: Color,
    Style: Style,
};

pub const ComptimeFarbe = struct {
    open: []const u8 = "",
    close: []const u8 = "",

    pub inline fn init() ComptimeFarbe {
        comptime return .{};
    }

    pub inline fn push(f: ComptimeFarbe, comptime cs: ColorStyle) ComptimeFarbe {
        switch (cs) {
            .Color => |c| {
                const end = if (c.bg) "\u{001B}[49m" else "\u{001B}[39m";
                comptime return .{
                    .open = f.open ++ formatAnsi(c.bg, c.r, c.g, c.b),
                    .close = f.open ++ end,
                };
            },
            .Style => |s| {
                comptime return .{
                    .open = f.open ++ std.fmt.comptimePrint(
                        "\u{001B}[{}m",
                        .{s.op},
                    ),
                    .close = f.close ++ std.fmt.comptimePrint(
                        "\u{001B}[{}m",
                        .{s.cl},
                    ),
                };
            },
        }
    }

    pub inline fn bgRgb(f: ComptimeFarbe, r: u8, g: u8, b: u8) ComptimeFarbe {
        const color: Color = .{ .bg = true, .r = r, .g = g, .b = b };
        return f.push(.{ .Color = color });
    }

    pub inline fn fgRgb(f: ComptimeFarbe, r: u8, g: u8, b: u8) ComptimeFarbe {
        const color: Color = .{ .bg = false, .r = r, .g = g, .b = b };
        return f.push(.{ .Color = color });
    }

    pub inline fn style(f: ComptimeFarbe, s: Style) ComptimeFarbe {
        return f.push(.{ .Style = s });
    }

    pub fn writeOpen(f: ComptimeFarbe, writer: anytype) !void {
        try writer.writeAll(f.open);
    }

    pub fn writeClose(f: ComptimeFarbe, writer: anytype) !void {
        try writer.writeAll(f.close);
    }

    pub fn runtime(f: ComptimeFarbe, allocator: std.mem.Allocator) Farbe {
        var color = Farbe.init(allocator);
        color.prefix = f.open;
        color.suffix = f.close;
        return color;
    }

    pub fn fixed(f: ComptimeFarbe) Farbe {
        var color = Farbe.initFixed();
        color.prefix = f.open;
        color.suffix = f.close;
        return color;
    }

    pub usingnamespace StyleMixin(ComptimeFarbe, false);
    pub usingnamespace OuputMixin(ComptimeFarbe);
};

pub const Farbe = struct {
    prefix: ?[]const u8 = null,
    suffix: ?[]const u8 = null,
    stack: ?std.ArrayList(ColorStyle),

    pub const Error = error{NoStack};

    pub fn init(allocator: std.mem.Allocator) Farbe {
        return .{
            .stack = std.ArrayList(ColorStyle).init(allocator),
        };
    }

    pub fn initFixed() Farbe {
        return .{ .stack = null };
    }

    pub fn deinit(f: *Farbe) void {
        if (f.stack) |stack| {
            stack.deinit();
        }
        f.* = undefined;
    }

    pub fn pop(f: *Farbe) !void {
        if (f.stack) |*stack| {
            _ = stack.pop();
        } else return Error.NoStack;
    }

    pub fn push(f: *Farbe, cs: ColorStyle) !void {
        if (f.stack) |*stack| {
            try stack.append(cs);
        } else return Error.NoStack;
    }

    pub fn bgRgb(f: *Farbe, r: u8, g: u8, b: u8) !void {
        const color: Color = .{ .bg = true, .r = r, .g = g, .b = b };
        try f.push(.{ .Color = color });
    }

    pub fn fgRgb(f: *Farbe, r: u8, g: u8, b: u8) !void {
        const color: Color = .{ .bg = false, .r = r, .g = g, .b = b };
        try f.push(.{ .Color = color });
    }

    pub fn style(f: *Farbe, s: Style) !void {
        try f.push(.{ .Style = s });
    }

    pub fn writeOpen(f: Farbe, writer: anytype) !void {
        if (f.prefix) |prefix| try writer.writeAll(prefix);
        if (f.stack) |stack| {
            const items = stack.items;
            for (items) |cs| {
                switch (cs) {
                    .Color => |c| try writeAnsi(writer, c.bg, c.r, c.g, c.b),
                    .Style => |s| try writer.print("\u{001B}[{}m", .{s.op}),
                }
            }
        }
    }

    pub fn writeClose(f: Farbe, writer: anytype) !void {
        if (f.stack) |stack| {
            const items = stack.items;
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
        if (f.suffix) |suffix| try writer.writeAll(suffix);
    }

    pub usingnamespace StyleMixin(Farbe, true);
    pub usingnamespace OuputMixin(Farbe);
};

fn StyleMixin(comptime Self: type, comptime Mutable: bool) type {
    const RetType = @typeInfo(@TypeOf(Self.style)).Fn.return_type.?;
    const WithTry = @typeInfo(RetType) == .ErrorUnion;
    const MaybeMutSelf = if (Mutable) *Self else Self;
    return struct {
        fn styleWrapper(f: MaybeMutSelf, s: Style) RetType {
            if (WithTry) {
                return try f.style(s);
            } else {
                return f.style(s);
            }
        }

        pub fn reset(f: MaybeMutSelf) RetType {
            return styleWrapper(f, Style.RESET);
        }

        pub fn bold(f: MaybeMutSelf) RetType {
            return styleWrapper(f, Style.BOLD);
        }

        pub fn dim(f: MaybeMutSelf) RetType {
            return styleWrapper(f, Style.DIM);
        }

        pub fn italic(f: MaybeMutSelf) RetType {
            return styleWrapper(f, Style.ITALIC);
        }

        pub fn underlined(f: MaybeMutSelf) RetType {
            return styleWrapper(f, Style.UNDERLINED);
        }

        pub fn inverse(f: MaybeMutSelf) RetType {
            return styleWrapper(f, Style.INVERSE);
        }

        pub fn hidden(f: MaybeMutSelf) RetType {
            return styleWrapper(f, Style.HIDDEN);
        }

        pub fn strikethrough(f: MaybeMutSelf) RetType {
            return styleWrapper(f, Style.STRIKETHROUGH);
        }

        pub fn overline(f: MaybeMutSelf) RetType {
            return styleWrapper(f, Style.OVERLINE);
        }
    };
}

fn OuputMixin(comptime Self: type) type {
    return struct {
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

test "comptime" {
    const farb = comptime ComptimeFarbe.init().italic().bold();
    try std.testing.expectEqualSlices(u8, &.{
        0x1B, 0x5B, 0x33, 0x6D, 0x1B, 0x5B, 0x31, 0x6D,
    }, farb.open);

    const farb2 = comptime ComptimeFarbe.init().fgRgb(255, 0, 0);
    try std.testing.expectEqualSlices(u8, &.{
        0x1B, 0x5B, 0x33, 0x38, 0x3B, 0x32, 0x3B, 0x32,
        0x35, 0x35, 0x3B, 0x30, 0x30, 0x30, 0x3B, 0x30,
        0x30, 0x30, 0x6D, 0x00,
    }, farb2.open);
}

test "runtime" {
    var farb = Farbe.init(std.testing.allocator);
    defer farb.deinit();

    try farb.italic();
    try farb.bold();

    const opener = try farb.open(std.testing.allocator);
    defer std.testing.allocator.free(opener);

    try std.testing.expectEqualSlices(u8, &.{
        0x1B, 0x5B, 0x33, 0x6D, 0x1B, 0x5B, 0x31, 0x6D,
    }, opener);
}

test "comptime to runtime" {
    const farb = comptime ComptimeFarbe.init();

    var farb_runtime = farb.runtime(std.testing.allocator);
    defer farb_runtime.deinit();
    try farb_runtime.italic();
    try farb_runtime.bold();

    const opener = try farb_runtime.open(std.testing.allocator);
    defer std.testing.allocator.free(opener);

    try std.testing.expectEqualSlices(u8, &.{
        0x1B, 0x5B, 0x33, 0x6D, 0x1B, 0x5B, 0x31, 0x6D,
    }, opener);
}

test "comptime to fixed" {
    const farb = comptime ComptimeFarbe.init().italic().bold();

    var farb_runtime = farb.fixed();
    defer farb_runtime.deinit();

    const opener = try farb_runtime.open(std.testing.allocator);
    defer std.testing.allocator.free(opener);

    try std.testing.expectEqualSlices(u8, &.{
        0x1B, 0x5B, 0x33, 0x6D, 0x1B, 0x5B, 0x31, 0x6D,
    }, opener);

    const outcome = farb_runtime.dim() catch |err| err;
    try std.testing.expectEqual(outcome, Farbe.Error.NoStack);
}
