const std = @import("std");
const builtin = @import("builtin");
const image = @import("image");
const term = @import("term");
const engine = @import("engine");

//TODO incorporate changes from zigxel and image libraries
pub const Image = image.Image;
pub const Graphics = engine.Graphics;

pub const Error = error{} || engine.Error || term.Error || Image.Error;
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

export fn render_img(name: [*:0]const u8, len: usize) usize {
    const name_slice: []const u8 = name[0..len];
    const extension: []const u8 = name_slice[len - 3 ..];
    var img: Image = undefined;
    if (std.mem.eql(u8, extension, "jpg")) {
        img = Image.init_load(allocator, name_slice, .JPEG) catch {
            return 1;
        };
    } else if (std.mem.eql(u8, extension, "bmp")) {
        img = Image.init_load(allocator, name_slice, .BMP) catch {
            return 1;
        };
    } else if (std.mem.eql(u8, extension, "png")) {
        img = Image.init_load(allocator, name_slice, .PNG) catch {
            return 1;
        };
    } else {
        std.log.info("Image must be .jpg/.png/.bmp\n", .{});
    }
    defer img.deinit();
    var g: Graphics = Graphics.init(allocator, .pixel, ._2d, .color_true, .wasm) catch {
        return 1;
    };
    const ratio = @as(f32, @floatFromInt(img.width)) / @as(f32, @floatFromInt(img.height));
    const height = @as(u32, @intCast(g.pixel.pixel_height));
    const width = @as(u32, @intFromFloat(@as(f32, @floatFromInt(g.pixel.pixel_height)) * ratio));
    const pixels = image.image_core.bilinear(allocator, img.data.items, img.width, img.height, width, height) catch {
        return 1;
    };
    defer allocator.free(pixels);
    g.pixel.first_render = false;
    g.pixel.draw_pixel_buffer(pixels, width, height, .{ .x = 0, .y = 0, .width = width, .height = height }, .{ .x = 0, .y = 0, .width = width, .height = height }, null) catch {
        return 1;
    };
    g.pixel.flip(null, null) catch {
        return 1;
    };
    if (builtin.os.tag != .emscripten) {
        _ = g.pixel.terminal.stdin.readByte() catch {
            return 1;
        };
    }
    g.deinit() catch {
        return 1;
    };
    return 0;
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
        std.log.warn("Leaked!\n", .{});
    }
}
