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

pub const Farbe = struct {
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

    pub fn bgRgb(f: *Farbe, r: u8, g: u8, b: u8) !void {
        const color: Color = .{ .bg = true, .r = r, .g = g, .b = b };
        try f.stack.append(.{ .Color = color });
    }

    pub fn fgRgb(f: *Farbe, r: u8, g: u8, b: u8) !void {
        const color: Color = .{ .bg = false, .r = r, .g = g, .b = b };
        try f.stack.append(.{ .Color = color });
    }

    pub fn writeOpen(f: Farbe, writer: anytype) !void {
        for (f.stack.items) |cs| {
            switch (cs) {
                .Color => |c| try writeAnsi16m(writer, c.bg, c.r, c.g, c.b),
                .Style => |s| try writer.print("\u{001B}[{}m", .{s.op}),
            }
        }
    }

    pub fn writeClose(f: Farbe, writer: anytype) !void {
        const end = f.stack.items.len;
        for (1..end) |i| {
            const cs = f.stack.items[end - i];
            switch (cs) {
                .Color => |c| try writer.writeAll(if (c.bg) "\u{001B}[39m" else "\u{001B}[49m"),
                .Style => |s| try writer.print("\u{001B}[{}m", .{s.op}),
            }
        }
    }

    /// Caller owns memory.
    pub fn open(f: Farbe, allocator: std.mem.Allocator) ![]const u8 {
        var buf = std.ArrayList(u8).init(allocator);
        var writer = buf.writer();
        try f.writeOpen(writer);
        return buf.toOwnedSlice();
    }

    /// Caller owns memory.
    pub fn close(f: Farbe, allocator: std.mem.Allocator) ![]const u8 {
        var buf = std.ArrayList(u8).init(allocator);
        var writer = buf.writer();
        try f.writeclose(writer);
        return buf.toOwnedSlice();
    }

    pub fn write(f: Farbe, writer: anytype, comptime fmt: []const u8, args: anytype) !void {
        try f.writeOpen(writer);
        try writer.print(fmt, args);
        try f.writeClose(writer);
    }
};
