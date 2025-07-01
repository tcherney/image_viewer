const std = @import("std");
const image = @import("image");
const term = @import("term");
const engine = @import("engine");

//TODO incorporate changes from zigxel and image libraries
pub const Image = image.Image;
pub const Graphics = engine.Graphics;

pub const Error = error{} || engine.Error || term.Error || Image.Error;

pub const std_options: std.Options = .{
    .log_level = .err,
    .logFn = myLogFn,
    .log_scope_levels = &[_]std.log.ScopeLevel{
        .{ .scope = .png_image, .level = .err },
        .{ .scope = .jpeg_image, .level = .err },
        .{ .scope = .bmp_image, .level = .err },
        .{ .scope = .texture, .level = .err },
        .{ .scope = .graphics, .level = .err },
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

pub fn render_img(img: *Image, allocator: std.mem.Allocator) Error!void {
    var g: Graphics = try Graphics.init(allocator, .pixel, ._2d, .color_true);
    const ratio = @as(f32, @floatFromInt(img.width)) / @as(f32, @floatFromInt(img.height));
    const height = @as(u32, @intCast(g.pixel.terminal.size.height));
    const width = @as(u32, @intFromFloat(@as(f32, @floatFromInt(g.pixel.terminal.size.height)) * ratio));
    std.log.info("width {d}, height {d}, width {d}, height {d} \n", .{ img.width, img.height, width, height });
    const pixels = try image.image_core.bilinear(allocator, img.data.items, img.width, img.height, width, height);
    defer allocator.free(pixels);
    g.pixel.first_render = false;
    try g.pixel.draw_pixel_buffer(pixels, width, height, .{ .x = 0, .y = 0, .width = width, .height = height }, .{ .x = 0, .y = 0, .width = width, .height = height }, null);
    try g.pixel.flip(null, null);
    _ = try g.pixel.terminal.stdin.readByte();
    try g.deinit();
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();
    const argsv = try std.process.argsAlloc(allocator);
    if (argsv.len > 1) {
        if (argsv.len >= 2) {
            if (argsv[1].len < 3) {
                try stdout.print("Image must be .jpg/.png/.bmp\n", .{});
                try bw.flush();
                return;
            } else {
                const extension = argsv[1][argsv[1].len - 3 ..];
                if (std.mem.eql(u8, extension, "jpg")) {
                    var im = try Image.init_load(allocator, argsv[1], .JPEG);
                    try render_img(&im, allocator);
                    im.deinit();
                } else if (std.mem.eql(u8, extension, "bmp")) {
                    var im = try Image.init_load(allocator, argsv[1], .BMP);
                    try render_img(&im, allocator);
                    im.deinit();
                } else if (std.mem.eql(u8, extension, "png")) {
                    var im = try Image.init_load(allocator, argsv[1], .PNG);
                    try render_img(&im, allocator);
                    im.deinit();
                } else {
                    try stdout.print("Image must be .jpg/.png/.bmp\n", .{});
                    try bw.flush();
                }
            }
        } else {
            try stdout.print("Usage: {s} image_file\n", .{argsv[0]});
            try bw.flush();
        }
    }

    std.process.argsFree(allocator, argsv);

    if (gpa.deinit() == .leak) {
        std.log.warn("Leaked!\n", .{});
    }
}
