const std = @import("std");
const builtin = @import("builtin");
const image = @import("image");
const term = @import("term");
const engine = @import("engine");

pub const Image = image.Image;
pub const Graphics = engine.Graphics;

pub const Error = error{BadFileExt} || engine.Error || term.Error || Image.Error;
var allocator: std.mem.Allocator = undefined;
pub const std_options: std.Options = .{
    .log_level = .err,
    .logFn = myLogFn,
    .log_scope_levels = &[_]std.log.ScopeLevel{
        .{ .scope = .png_image, .level = .err },
        .{ .scope = .jpeg_image, .level = .err },
        .{ .scope = .bmp_image, .level = .err },
        .{ .scope = .texture, .level = .err },
        .{ .scope = .graphics, .level = .err },
        .{ .scope = .image_viewer, .level = .info },
        .{ .scope = .pixel_renderer, .level = .info },
        .{ .scope = .common, .level = .info },
    },
};

pub fn myLogFn(
    comptime level: std.log.Level,
    comptime scope: @TypeOf(.enum_literal),
    comptime format: []const u8,
    args: anytype,
) void {
    const prefix = "[" ++ comptime level.asText() ++ "] (" ++ @tagName(scope) ++ "): ";
    // Print the message to stderr, silently ignoring any errors
    std.debug.lockStdErr();
    defer std.debug.unlockStdErr();
    const stderr = std.io.getStdErr().writer();
    nosuspend stderr.print(prefix ++ format, args) catch return;
}

const IMAGEVIEWER_LOG = std.log.scoped(.image_viewer);

export fn render_img(name: [*:0]const u8, len: usize) usize {
    const name_slice: []const u8 = name[0..len];
    var ret: usize = 0;
    render(name_slice) catch |err| {
        IMAGEVIEWER_LOG.err("Error occured: {any}\n", .{err});
        ret = 1;
    };

    return 0;
}

pub fn render(name: []const u8) Error!void {
    const extension: []const u8 = name[name.len - 3 ..];
    var img: Image = undefined;
    if (std.mem.eql(u8, extension, "jpg") or std.mem.eql(u8, name[name.len - 4 ..], "jpeg")) {
        img = try Image.init_load(allocator, name, .JPEG);
    } else if (std.mem.eql(u8, extension, "bmp")) {
        img = try Image.init_load(allocator, name, .BMP);
    } else if (std.mem.eql(u8, extension, "png")) {
        img = try Image.init_load(allocator, name, .PNG);
    } else {
        IMAGEVIEWER_LOG.err("Image must be .jpg/.png/.bmp\n", .{});
        return Error.BadFileExt;
    }
    defer img.deinit();
    engine.set_wasm_terminal_size(150, 600);
    const sixel_mode = true;
    if (sixel_mode) {
        var g: Graphics = try Graphics.init(allocator, .sixel, ._2d, .color_true, if (builtin.os.tag == .emscripten or builtin.os.tag == .wasi) .wasm else .native);
        //const ratio = @as(f32, @floatFromInt(img.width)) / @as(f32, @floatFromInt(img.height));
        const height = 45 * 6; //@as(u32, @intCast(g.pixel.pixel_height));
        const width = 68 * 6; //@as(u32, @intFromFloat(@as(f32, @floatFromInt(g.pixel.pixel_height)) * ratio));
        const pixels = try image.image_core.bilinear(allocator, img.data.items, img.width, img.height, width, height);
        defer allocator.free(pixels);
        //g.pixel.first_render = false;
        IMAGEVIEWER_LOG.info("Rendering image of size {d}x{d} terminal size {d}x{d}\n", .{ width, height, g.pixel.pixel_width, g.pixel.pixel_height });
        g.pixel.set_bg(0, 0, 0, null);
        try g.pixel.draw_pixel_buffer(pixels, width, height, .{ .x = 0, .y = 0, .width = width, .height = height }, .{ .x = 0, .y = 0, .width = width, .height = height }, null);
        try g.pixel.flip(null, .{ .x = 0, .y = 0, .width = width, .height = height });
        if (builtin.os.tag != .emscripten) {
            _ = try g.pixel.terminal.stdin.readByte();
        }
        try g.deinit();
    } else {
        var g: Graphics = try Graphics.init(allocator, .pixel, ._2d, .color_true, if (builtin.os.tag == .emscripten or builtin.os.tag == .wasi) .wasm else .native);
        const ratio = @as(f32, @floatFromInt(img.width)) / @as(f32, @floatFromInt(img.height));
        const height = @as(u32, @intCast(g.pixel.pixel_height));
        const width = @as(u32, @intFromFloat(@as(f32, @floatFromInt(g.pixel.pixel_height)) * ratio));
        const pixels = try image.image_core.bilinear(allocator, img.data.items, img.width, img.height, width, height);
        defer allocator.free(pixels);
        //g.pixel.first_render = false;
        IMAGEVIEWER_LOG.info("Rendering image of size {d}x{d} terminal size {d}x{d}\n", .{ width, height, g.pixel.pixel_width, g.pixel.pixel_height });
        g.pixel.set_bg(0, 0, 0, null);
        try g.pixel.draw_pixel_buffer(pixels, width, height, .{ .x = 0, .y = 0, .width = width, .height = height }, .{ .x = 0, .y = 0, .width = width, .height = height }, null);
        try g.pixel.flip(null, .{
            .x = 0,
            .y = 0,
            .width = width,
            .height = height,
        });
        if (builtin.os.tag != .emscripten) {
            _ = try g.pixel.terminal.stdin.readByte();
        }
        try g.deinit();
    }
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    if (builtin.os.tag == .emscripten) {
        allocator = std.heap.c_allocator;
    } else {
        allocator = gpa.allocator();
    }
    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();
    const argsv = try std.process.argsAlloc(allocator);
    if (argsv.len > 1) {
        if (argsv.len >= 2) {
            const dupe = try allocator.dupeZ(u8, argsv[1]);
            defer allocator.free(dupe);
            _ = render_img(dupe, argsv[1].len);
        } else {
            try stdout.print("Usage: {s} image_file\n", .{argsv[0]});
            try bw.flush();
        }
    }

    std.process.argsFree(allocator, argsv);

    if (builtin.os.tag != .emscripten and gpa.deinit() == .leak) {
        IMAGEVIEWER_LOG.warn("Leaked!\n", .{});
    }
}
