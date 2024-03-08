const std = @import("std");
const farbe = @import("farbe");

fn colorTest(
    alloc: std.mem.Allocator,
) !void {
    var writer = std.io.getStdOut().writer();

    try writer.writeAll("Comptime Color Test\n");
    {
        const c1 = farbe.ComptimeFarbe.init().bgRgb(255, 0, 0).fgRgb(0, 255, 255).fixed();
        try c1.write(writer, "Bg Red Fg Cyan", .{});
    }
    try writer.writeAll(" Reset\n");
    {
        const c1 = farbe.ComptimeFarbe.init().bgRgb(255, 255, 255).fgRgb(0, 0, 0).underlined().fixed();
        try c1.write(writer, "Bg White Fb Black Underlined", .{});
    }
    try writer.writeAll(" Reset\n");

    try writer.writeAll("Runtime Color Test\n");
    {
        var c1 = farbe.Farbe.init(alloc);
        defer c1.deinit();
        try c1.bgRgb(255, 0, 0);
        try c1.fgRgb(0, 255, 255);
        try c1.write(writer, "Bg Red Fg Cyan", .{});
    }
    try writer.writeAll(" Reset\n");
    {
        var c1 = farbe.Farbe.init(alloc);
        defer c1.deinit();
        try c1.bgRgb(255, 255, 255);
        try c1.fgRgb(0, 0, 0);
        try c1.underlined();
        try c1.write(writer, "Bg White Fb Black Underlined", .{});
    }
    try writer.writeAll(" Reset\n");
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    // eat prog name
    _ = args.next();

    // are there ary args?
    const maybe_arg = args.next();
    const r_string = maybe_arg orelse {
        try colorTest(allocator);
        std.process.exit(0);
    };

    const r = try std.fmt.parseInt(u8, r_string, 10);
    const g = try std.fmt.parseInt(u8, args.next() orelse "0", 10);
    const b = try std.fmt.parseInt(u8, args.next() orelse "0", 10);

    if (args.next()) |_| {
        try std.io.getStdErr().writeAll("Too many arguments. Expected 3.\n");
        std.os.exit(1);
    }
    var color = farbe.Farbe.init(allocator);
    defer color.deinit();

    try color.fgRgb(r, g, b);
    var stdout = std.io.getStdOut().writer();
    try stdout.print("R {} G {} B {}\n", .{ r, g, b });
    try color.write(stdout, "██", .{});
    try stdout.writeAll(" ");
    try color.write(stdout, "Sample Text", .{});

    try color.italic();
    try stdout.writeAll(" ");
    try color.write(stdout, "Sample Text", .{});

    try color.pop();

    try color.bold();
    try stdout.writeAll(" ");
    try color.write(stdout, "Sample Text", .{});

    try color.pop();

    try color.underlined();
    try stdout.writeAll(" ");
    try color.write(stdout, "Sample Text", .{});

    try stdout.writeAll("\n");

    std.os.exit(0);
}
