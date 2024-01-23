const std = @import("std");
const farbe = @import("farbe");

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
