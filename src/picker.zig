const std = @import("std");
const farbe = @import("farbe");

const TermInfo = std.os.termios;

const ESCAPE = 27; // escape code
const ARROW_UP = 'A';
const ARROW_DOWN = 'B';
const ARROW_RIGHT = 'C';
const ARROW_LEFT = 'D';

const CURSOR_COLUMN = 'G';
const CURSOR_HIDE = "\x1b[?25l";
const CURSOR_VISIBLE = "\x1b[?25h";

const LINE_CLEAR = 'K';

const Input = union(enum) {
    char: u8,
    escaped: u8,
    Up,
    Down,
    Right,
    Left,

    pub fn translateEscaped(num: u8, c: u8) Input {
        _ = num;
        return switch (c) {
            ARROW_UP => .Up,
            ARROW_DOWN => .Down,
            ARROW_RIGHT => .Right,
            ARROW_LEFT => .Left,
            else => .{ .escaped = c },
        };
    }
};

const TtyFd = struct {
    file: std.fs.File,
    original: std.os.termios,
    current: std.os.termios,

    fn setTerm(handle: std.fs.File.Handle, term: std.os.termios) !void {
        try std.os.tcsetattr(handle, .NOW, term);
    }

    pub fn deinit(tf: *TtyFd) void {
        setTerm(tf.file.handle, tf.original) catch unreachable;
        tf.* = undefined;
    }

    pub fn init(file: std.fs.File) !TtyFd {
        const original = try std.os.tcgetattr(file.handle);
        var current = original;

        // local: no echo, canonical mode, remove signals
        current.lflag.ECHO = false;
        current.lflag.ICANON = false;
        current.lflag.ISIG = false;
        // input: translate carriage return to newline
        current.iflag.ICRNL = false;

        // return read after each byte is sent
        current.cc[@intFromEnum(std.os.linux.V.MIN)] = 1;
        try setTerm(file.handle, current);

        return .{ .file = file, .original = original, .current = current };
    }
};

const TermUI = struct {
    allocator: std.mem.Allocator,
    in: TtyFd,
    out: TtyFd,

    pub fn writeEscaped(tui: *TermUI, mod: usize, key: u8) !void {
        try tui.print("\x1b[{d}{c}", .{ mod, key });
    }

    pub fn writer(tui: *TermUI) std.fs.File.Writer {
        return tui.out.file.writer();
    }

    pub fn reader(tui: *TermUI) std.fs.File.Reader {
        return tui.in.file.reader();
    }

    pub fn nextInput(tui: *TermUI) !Input {
        const rdr = tui.reader();
        const c = try rdr.readByte();
        switch (c) {
            ESCAPE => {
                const num = try rdr.readByte();
                const key = try rdr.readByte();
                return Input.translateEscaped(num, key);
            },
            else => return .{ .char = c },
        }
    }

    pub fn print(tui: *TermUI, comptime fmt: []const u8, args: anytype) !void {
        try tui.writer().print(fmt, args);
    }

    pub fn getSize(tui: *TermUI) usize {
        return std.os.linux.ioctl(tui.handle, std.os.linux.T.IOCGWINSZ, 0);
    }

    pub fn init(
        allocator: std.mem.Allocator,
        stdin: std.fs.File,
        stdout: std.fs.File,
    ) !TermUI {
        var in = try TtyFd.init(stdin);
        errdefer in.deinit();
        var out = try TtyFd.init(stdout);
        errdefer out.deinit();

        return .{
            .allocator = allocator,
            .in = in,
            .out = out,
        };
    }

    pub fn deinit(tui: *TermUI) void {
        // probably show the cursor again
        tui.out.deinit();
        tui.in.deinit();
        tui.* = undefined;
    }

    // Cursor control

    pub fn cursorUp(tui: *TermUI, num: usize) !void {
        try tui.writeEscaped(num, ARROW_UP);
    }
    pub fn cursorDown(tui: *TermUI, num: usize) !void {
        try tui.writeEscaped(num, ARROW_DOWN);
    }
    pub fn cursorRight(tui: *TermUI, num: usize) !void {
        try tui.writeEscaped(num, ARROW_RIGHT);
    }
    pub fn cursorLeft(tui: *TermUI, num: usize) !void {
        try tui.writeEscaped(num, ARROW_LEFT);
    }
    pub fn cursorToColumn(tui: *TermUI, col: usize) !void {
        try tui.writeEscaped(col, CURSOR_COLUMN);
    }

    pub fn clearCurrentLine(tui: *TermUI) !void {
        try tui.cursorToColumn(1);
        try tui.writeEscaped(2, LINE_CLEAR);
    }

    pub fn cursorVisible(tui: *TermUI, visible: bool) !void {
        if (visible) {
            try tui.writer().writeAll(CURSOR_VISIBLE);
        } else {
            try tui.writer().writeAll(CURSOR_HIDE);
        }
    }
};

const Picker = struct {
    tui: TermUI,
    allocator: std.mem.Allocator,

    // digits
    digits: [9]u8 = .{0} ** 9,
    cursor_pos: usize = 0,

    pub fn init(allocator: std.mem.Allocator) !Picker {
        const stdout = std.io.getStdOut();
        const stdin = std.io.getStdIn();

        var tui = try TermUI.init(allocator, stdin, stdout);
        errdefer tui.deinit();

        try tui.cursorVisible(false);
        return .{ .tui = tui, .allocator = allocator };
    }

    pub fn deinit(p: *Picker) void {
        p.tui.cursorVisible(true) catch {};
        p.tui.deinit();
        p.* = undefined;
    }

    fn capDigits(ds: []u8) void {
        // bound checking
        if (ds[0] > 1) {
            ds[1] = @min(ds[1], 5);
            ds[2] = @min(ds[2], 5);
        }
    }

    fn capValues(p: *Picker) void {
        // bound checking
        capDigits(p.digits[0..3]);
        capDigits(p.digits[3..6]);
        capDigits(p.digits[6..9]);
    }

    fn digitsToNumber(ds: []const u8) u8 {
        return 100 * ds[0] + 10 * ds[1] + ds[2];
    }

    pub fn readValues(p: *const Picker) [3]u8 {
        return .{
            digitsToNumber(p.digits[0..3]),
            digitsToNumber(p.digits[3..6]),
            digitsToNumber(p.digits[6..9]),
        };
    }

    pub fn display(p: *Picker, with_cursor: bool) !void {
        // reset to start of line
        try p.tui.clearCurrentLine();

        var writer = p.tui.writer();

        for (0.., p.digits) |i, d| {
            if (i % 3 == 0) try writer.writeByte(' ');
            if (with_cursor and i == p.cursor_pos) {
                // write with colours
                const color = farbe.ComptimeFarbe.init().bgRgb(255, 255, 255).fgRgb(0, 0, 0).fixed();
                try color.write(writer, "{d}", .{d});
            } else {
                try writer.print("{d}", .{d});
            }
        }

        try writer.writeByteNTimes(' ', 3);

        const values = p.readValues();
        var f = farbe.Farbe.init(p.allocator);
        defer f.deinit();
        try writer.writeByteNTimes(' ', 3);

        try f.fgRgb(values[0], values[1], values[2]);

        try f.write(writer, "██", .{});
        try writer.writeByte(' ');

        try f.write(writer, "Sample Text", .{});
    }

    fn moveCursor(p: *Picker, lr: enum { Left, Right }) void {
        switch (lr) {
            .Left => {
                p.cursor_pos = @max(0, p.cursor_pos -| 1);
            },
            .Right => {
                p.cursor_pos = @min(8, p.cursor_pos +| 1);
            },
        }
    }

    fn currentMaxValue(p: *const Picker) u8 {
        const offset = p.cursor_pos % 3;
        return if (offset == 0)
            2
        else if (p.digits[p.cursor_pos - offset] == 2)
            5
        else
            9;
    }

    fn setValue(p: *Picker, value: u8) void {
        p.digits[p.cursor_pos] = @min(p.currentMaxValue(), value);
    }

    fn adjustValue(p: *Picker, ud: enum { Up, Down }) void {
        const i = p.cursor_pos;
        const max_value = p.currentMaxValue();

        switch (ud) {
            .Down => {
                if (p.digits[i] > 0) {
                    p.digits[i] -= 1;
                }
            },
            .Up => {
                if (p.digits[i] < max_value) {
                    p.digits[i] += 1;
                }
            },
        }
    }

    pub fn update(p: *Picker) !bool {
        try p.display(true);

        // get input
        const inp = try p.tui.nextInput();
        switch (inp) {
            .char => |c| switch (c) {
                'q' => return false,
                'h' => p.moveCursor(.Left),
                'l' => p.moveCursor(.Right),
                'k' => p.adjustValue(.Up),
                'j' => p.adjustValue(.Down),
                '0'...'9' => |d| {
                    p.setValue(d - '0');
                    p.moveCursor(.Right);
                },
                else => {},
            },
            .escaped => |e| {
                try p.tui.writer().print(">{c}<", .{e});
            },
            .Left => p.moveCursor(.Left),
            .Right => p.moveCursor(.Right),
            .Up => p.adjustValue(.Up),
            .Down => p.adjustValue(.Down),
        }

        p.capValues();
        return true;
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var picker = try Picker.init(allocator);
    defer picker.deinit();

    while (true) {
        if (!try picker.update()) break;
    }

    try picker.display(false);
    try picker.tui.writer().writeByte('\n');
}
