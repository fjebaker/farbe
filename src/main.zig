const std = @import("std");

const BACKGROUND_CODE = 48;
const FOREGROUND_CODE = 38;

fn formatAnsi(
    bg: bool,
    r: u8,
    g: u8,
    b: u8,
) [19]u8 {
    const bg_int: u8 = if (bg) BACKGROUND_CODE else FOREGROUND_CODE;
    var buf: [19]u8 = undefined;
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
    r: u8,
    g: u8,
    b: u8,
};

pub const AnsiStyleFormat = struct {
    op: u8,
    cl: u8,
};

const AnsiStyleFormatMap = std.StaticStringMap(AnsiStyleFormat).initComptime(&.{
    .{ "reset", AnsiStyleFormat{ .op = 0, .cl = 0 } },
    .{ "bold", AnsiStyleFormat{ .op = 1, .cl = 22 } },
    .{ "dim", AnsiStyleFormat{ .op = 2, .cl = 22 } },
    .{ "italic", AnsiStyleFormat{ .op = 3, .cl = 23 } },
    .{ "underlined", AnsiStyleFormat{ .op = 4, .cl = 24 } },
    .{ "inverse", AnsiStyleFormat{ .op = 7, .cl = 27 } },
    .{ "hidden", AnsiStyleFormat{ .op = 8, .cl = 28 } },
    .{ "strikethrough", AnsiStyleFormat{ .op = 9, .cl = 29 } },
    .{ "overline", AnsiStyleFormat{ .op = 53, .cl = 55 } },
});

pub const Style = struct {
    reset: bool = false,
    bold: bool = false,
    dim: bool = false,
    italic: bool = false,
    underlined: bool = false,
    inverse: bool = false,
    hidden: bool = false,
    strikethrough: bool = false,
    overline: bool = false,
};

pub const ColorStyle = union(enum) {
    Color: Color,
    Style: Style,
};

pub const Farbe = struct {
    fg: ?Color = null,
    bg: ?Color = null,
    style: Style = .{},

    pub fn init() Farbe {
        return .{};
    }

    pub fn bgRgb(f: Farbe, r: u8, g: u8, b: u8) Farbe {
        var new = f;
        new.bg = .{ .r = r, .g = g, .b = b };
        return new;
    }

    pub fn fgRgb(f: Farbe, r: u8, g: u8, b: u8) Farbe {
        var new = f;
        new.fg = .{ .r = r, .g = g, .b = b };
        return new;
    }

    pub fn setStyle(f: *Farbe, s: Style) !void {
        f.style = s;
    }

    pub fn writeOpen(f: Farbe, writer: anytype) !void {
        inline for (@typeInfo(Style).@"struct".fields) |field| {
            if (@field(f.style, field.name)) {
                try writer.print(
                    "\u{001B}[{d}m",
                    .{AnsiStyleFormatMap.get(field.name).?.op},
                );
            }
        }
        if (f.bg) |bg| {
            try writeAnsi(writer, true, bg.r, bg.g, bg.b);
        }
        if (f.fg) |fg| {
            try writeAnsi(writer, false, fg.r, fg.g, fg.b);
        }
    }

    pub fn writeClose(f: Farbe, writer: anytype) !void {
        if (f.fg) |_| {
            try writer.writeAll("\u{001B}[39m");
        }
        if (f.bg) |_| {
            try writer.writeAll("\u{001B}[49m");
        }
        inline for (@typeInfo(Style).@"struct".fields) |field| {
            if (@field(f.style, field.name)) {
                try writer.print(
                    "\u{001B}[{d}m",
                    .{AnsiStyleFormatMap.get(field.name).?.cl},
                );
            }
        }
    }

    inline fn styleWrapper(f: Farbe, style: Style) Farbe {
        var s: Style = f.style;
        inline for (@typeInfo(Style).@"struct".fields) |field| {
            @field(s, field.name) =
                @field(s, field.name) or @field(style, field.name);
        }

        var new = f;
        new.style = s;
        return new;
    }

    pub inline fn reset(f: Farbe) Farbe {
        return styleWrapper(f, .{ .reset = true });
    }

    pub inline fn bold(f: Farbe) Farbe {
        return styleWrapper(f, .{ .bold = true });
    }

    pub inline fn dim(f: Farbe) Farbe {
        return styleWrapper(f, .{ .dim = true });
    }

    pub inline fn italic(f: Farbe) Farbe {
        return styleWrapper(f, .{ .italic = true });
    }

    pub inline fn underlined(f: Farbe) Farbe {
        return styleWrapper(f, .{ .underlined = true });
    }

    pub inline fn inverse(f: Farbe) Farbe {
        return styleWrapper(f, .{ .inverse = true });
    }

    pub inline fn hidden(f: Farbe) Farbe {
        return styleWrapper(f, .{ .hidden = true });
    }

    pub inline fn strikethrough(f: Farbe) Farbe {
        return styleWrapper(f, Style.STRIKETHROUGH);
    }

    pub inline fn overline(f: Farbe) Farbe {
        return styleWrapper(f, Style.OVERLINE);
    }
    /// Caller owns memory.
    pub fn open(f: Farbe, allocator: std.mem.Allocator) ![]const u8 {
        var buf = std.ArrayList(u8).init(allocator);
        const writer = buf.writer();
        try f.writeOpen(writer);
        return buf.toOwnedSlice();
    }

    /// Caller owns memory.
    pub fn close(f: Farbe, allocator: std.mem.Allocator) ![]const u8 {
        var buf = std.ArrayList(u8).init(allocator);
        const writer = buf.writer();
        try f.writeclose(writer);
        return buf.toOwnedSlice();
    }

    // Writes the formatted text using the current colour and style
    // configuration.
    pub fn write(
        f: Farbe,
        writer: anytype,
        comptime fmt: []const u8,
        args: anytype,
    ) !void {
        try f.writeOpen(writer);
        try writer.print(fmt, args);
        try f.writeClose(writer);
    }
};

fn testEqualCode(
    comptime expected: []const u8,
    farb: Farbe,
    what: enum { open, close, full },
) !void {
    var buf = std.ArrayList(u8).init(std.testing.allocator);
    defer buf.deinit();

    try switch (what) {
        .open => farb.writeOpen(buf.writer()),
        .close => farb.writeClose(buf.writer()),
        .full => farb.write(buf.writer(), "", .{}),
    };

    try std.testing.expectEqualSlices(
        u8,
        expected,
        buf.items,
    );
}

test "comptime" {
    const farb = comptime Farbe.init().italic().bold();
    try testEqualCode(
        &.{ 0x1B, 0x5B, 0x31, 0x6D, 0x1B, 0x5B, 0x33, 0x6D },
        farb,
        .open,
    );

    const farb2 = comptime Farbe.init().fgRgb(255, 0, 0);
    try testEqualCode(
        &.{
            0x1B, 0x5B, 0x33, 0x38, 0x3B, 0x32, 0x3B, 0x32,
            0x35, 0x35, 0x3B, 0x30, 0x30, 0x30, 0x3B, 0x30,
            0x30, 0x30, 0x6D,
        },
        farb2,
        .open,
    );

    const farb3 = Farbe.init().fgRgb(255, 0, 0).bold();
    try testEqualCode(
        &.{
            0x1B, 0x5B, 0x31, 0x6D, 0x1B, 0x5B, 0x33, 0x38,
            0x3B, 0x32, 0x3B, 0x32, 0x35, 0x35, 0x3B, 0x30,
            0x30, 0x30, 0x3B, 0x30, 0x30, 0x30, 0x6D,
        },
        farb3,
        .open,
    );
}

test "runtime" {
    const farb = Farbe.init().italic().bold();
    try testEqualCode(
        &.{ 0x1B, 0x5B, 0x31, 0x6D, 0x1B, 0x5B, 0x33, 0x6D },
        farb,
        .open,
    );
}

test "comptime to runtime" {
    const farb = comptime Farbe.init();
    const farb_runtime = farb.italic().bold();

    const opener = try farb_runtime.open(std.testing.allocator);
    defer std.testing.allocator.free(opener);

    try std.testing.expectEqualSlices(
        u8,
        &.{ 0x1B, 0x5B, 0x31, 0x6D, 0x1B, 0x5B, 0x33, 0x6D },
        opener,
    );
}

test "writing" {
    var list = std.ArrayList(u8).init(std.testing.allocator);
    defer list.deinit();

    var farb = Farbe.init().italic().bold();

    try farb.write(list.writer(), "{s}", .{"test"});
    try std.testing.expectEqualSlices(u8, &.{
        0x1B, 0x5B, 0x31, 0x6D, 0x1B, 0x5B, 0x33, 0x6D,
        0x74, 0x65, 0x73, 0x74,
        // first closing tag
        0x1B, 0x5B, 0x32, 0x32,
        0x6D,
        // second closing tag
        0x1B, 0x5B, 0x32, 0x33, 0x6D,
    }, list.items);
}

test "comptime to fixed" {
    const farb = comptime Farbe.init().italic().bold();

    const opener = try farb.open(std.testing.allocator);
    defer std.testing.allocator.free(opener);

    try std.testing.expectEqualSlices(u8, &.{
        0x1B, 0x5B, 0x31, 0x6D, 0x1B, 0x5B, 0x33, 0x6D,
    }, opener);
}
