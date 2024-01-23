const std = @import("std");

pub inline fn wrapStyle(style: [2][]const u8) [2][]const u8 {
    return [_][]const u8{ "\u{001B}[" ++ style[0] ++ "m", "\u{001B}[" ++ style[1] ++ "m" };
}

pub fn wrapAnsi16m(
    allocator: std.mem.Allocator,
    bg: bool,
    r: u8,
    g: u8,
    b: u8,
) ![]const u8 {
    const bg_int: u8 = if (bg) 48 else 38;
    return std.fmt.allocPrint(
        allocator,
        "\u{001B}[{};2;{};{};{}m",
        .{ bg_int, r, g, b },
    );
}

pub const Colorful = struct {
    pub const Color = struct {
        open: []const u8,
        close: []const u8,
    };

    const ANSI16M_CLOSE = "\u{001B}[39m";

    arena: std.heap.ArenaAllocator,
    stack: std.ArrayList(Color),

    pub fn init(allocator: std.mem.Allocator) Colorful {
        return .{
            .arena = std.heap.ArenaAllocator.init(allocator),
            .stack = std.ArrayList(Color).init(allocator),
        };
    }

    pub fn deinit(c: *Colorful) void {
        c.stack.deinit();
        c.arena.deinit();
        c.* = undefined;
    }

    pub fn backgroundRgb(c: *Colorful, r: u8, g: u8, b: u8) !void {
        const color: Color = .{
            .open = try wrapAnsi16m(c.arena.allocator(), true, r, g, b),
            .close = ANSI16M_CLOSE,
        };
        try c.stack.append(color);
    }
    pub fn foregroundRgb(c: *Colorful, r: u8, g: u8, b: u8) !void {
        const color: Color = .{
            .open = try wrapAnsi16m(c.arena.allocator(), false, r, g, b),
            .close = ANSI16M_CLOSE,
        };
        try c.stack.append(color);
    }

    pub fn open(c: Colorful) ![]const u8 {
        return c.stack.items[0].open;
    }

    pub fn close(c: Colorful) ![]const u8 {
        return c.stack.items[0].close;
    }
};

pub fn writeColored(
    writer: anytype,
    color: Colorful,
    comptime fmt: []const u8,
    args: anytype,
) !void {
    try writer.writeAll(try color.open());
    try writer.print(fmt, args);
    try writer.writeAll(try color.close());
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    var allocator = gpa.allocator();

    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    // eat prog name
    _ = args.next();

    const r = try std.fmt.parseInt(u8, args.next() orelse "0", 10);
    const g = try std.fmt.parseInt(u8, args.next() orelse "0", 10);
    const b = try std.fmt.parseInt(u8, args.next() orelse "0", 10);

    if (args.next()) |_| {
        try std.io.getStdErr().writeAll("Too many arguments. Expected 3.\n");
        std.os.exit(1);
    }
    var color = Colorful.init(allocator);
    defer color.deinit();
    try color.foregroundRgb(r, g, b);

    var stdout = std.io.getStdOut().writer();
    try stdout.print("R {} G {} B {}\n", .{ r, g, b });
    try writeColored(stdout, color, "██", .{});
    try stdout.writeAll("\n");

    std.os.exit(0);
}
