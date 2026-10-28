const std = @import("std");
const c = @import("c");

// ---------------------------------------------------------------------------
// Appearance
// ---------------------------------------------------------------------------

const font_names = [_][*:0]const u8{ "DejaVu Sans Mono", "Noto Sans CJK JP", "Noto Color Emoji" };
const font_px = 14;
const bar_height = 22;
const tag_count = 9;
const tag_pad = 5;
const title_pad = 4;
const title_gap = 4;
const right_pad = 6;

const col_bg = 0x1f1f1f;
const col_accent = 0x17697d;
const col_urgent = 0x9e2a2b;
const col_bright = 0xe8e8e8;
const col_dim = 0x6c6c6c;
const col_label = 0x9a9a9a;
const col_media = 0xd75fd7;
const col_date = 0xcfcfcf;

fn rgb(hex: u24) c.pixman_color_t {
    const r: u16 = @intCast((hex >> 16) & 0xff);
    const g: u16 = @intCast((hex >> 8) & 0xff);
    const b: u16 = @intCast(hex & 0xff);
    return .{ .red = r * 257, .green = g * 257, .blue = b * 257, .alpha = 0xffff };
}

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

const Bar = struct {
    output: *c.wl_output,
    global_name: u32,
    status: ?*c.zriver_output_status_v1 = null,
    surface: ?*c.wl_surface = null,
    layer_surface: ?*c.zwlr_layer_surface_v1 = null,
    width: u32 = 0,
    scale: i32 = 1,
    pending_scale: i32 = 1,
    configured: bool = false,
    dirty: bool = false,
    focused_tags: u32 = 0,
    occupied_tags: u32 = 0,
    urgent_tags: u32 = 0,
    font: ?*c.fcft_font = null,
    font_bold: ?*c.fcft_font = null,
};

const max_bars = 8;

var display: *c.wl_display = undefined;
var compositor: ?*c.wl_compositor = null;
var shm: ?*c.wl_shm = null;
var layer_shell: ?*c.zwlr_layer_shell_v1 = null;
var status_manager: ?*c.zriver_status_manager_v1 = null;
var seat: ?*c.wl_seat = null;
var seat_status: ?*c.zriver_seat_status_v1 = null;
var bars: [max_bars]?*Bar = @splat(null);
var initialized = false;

var focused_output: ?*c.wl_output = null;
var title_buf: [512]u8 = undefined;
var title: []const u8 = "";

var mem_buf: [16]u8 = undefined;
var mem: []const u8 = "";
var vol_buf: [16]u8 = undefined;
var vol: []const u8 = "";
var media_buf: [512]u8 = undefined;
var media: []const u8 = "";
var date_buf: [64]u8 = undefined;
var date: []const u8 = "";

fn markAllDirty() void {
    for (bars) |maybe| if (maybe) |bar| {
        bar.dirty = true;
    };
}

// ---------------------------------------------------------------------------
// Status sources
// ---------------------------------------------------------------------------

fn updateMem() void {
    const f = c.fopen("/proc/meminfo", "r") orelse return;
    defer _ = c.fclose(f);
    var line: [128]u8 = undefined;
    var total: u64 = 0;
    var avail: u64 = 0;
    while (c.fgets(&line, line.len, f) != null) {
        const s = std.mem.sliceTo(&line, 0);
        var it = std.mem.tokenizeAny(u8, s, ": \n");
        const key = it.next() orelse continue;
        const val = std.fmt.parseInt(u64, it.next() orelse continue, 10) catch continue;
        if (std.mem.eql(u8, key, "MemTotal")) total = val;
        if (std.mem.eql(u8, key, "MemAvailable")) avail = val;
    }
    if (total == 0) return;
    const pct = @as(f64, @floatFromInt(total - avail)) * 100.0 / @as(f64, @floatFromInt(total));
    mem = std.fmt.bufPrint(&mem_buf, "{d:.1}%", .{pct}) catch "";
}

/// Runs a shell command and returns its first line of output, or null on failure.
fn readCommand(cmd: [*:0]const u8, buf: []u8) ?[]const u8 {
    const p = c.popen(cmd, "r") orelse return null;
    const got = c.fgets(buf.ptr, @intCast(buf.len), p);
    const rc = c.pclose(p);
    if (got == null or rc != 0) return null;
    const line = std.mem.trimEnd(u8, std.mem.sliceTo(buf, 0), "\r\n ");
    return if (line.len == 0) null else line;
}

fn updateVol() void {
    var out: [64]u8 = undefined;
    const line = readCommand("wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null", &out) orelse {
        vol = "";
        return;
    };
    // "Volume: 0.50" optionally followed by " [MUTED]"
    var it = std.mem.tokenizeScalar(u8, line, ' ');
    _ = it.next();
    const level = std.fmt.parseFloat(f64, it.next() orelse return) catch return;
    if (std.mem.indexOf(u8, line, "MUTED") != null) {
        vol = "muted";
        return;
    }
    vol = std.fmt.bufPrint(&vol_buf, "{d:.0}%", .{level * 100.0}) catch "";
}

fn updateMedia() void {
    media = readCommand(
        "playerctl -p spotify metadata --format '{{title}} - {{artist}}' 2>/dev/null",
        &media_buf,
    ) orelse "";
}

fn updateDate() void {
    var now = c.time(null);
    var tm: c.struct_tm = undefined;
    _ = c.localtime_r(&now, &tm);
    const n = c.strftime(&date_buf, date_buf.len, "%d/%b/%Y %-I:%M:%S %p", &tm);
    date = date_buf[0..n];
}

fn updateStatus() void {
    updateMem();
    updateVol();
    updateMedia();
    updateDate();
    markAllDirty();
}

// ---------------------------------------------------------------------------
// Drawing
// ---------------------------------------------------------------------------

fn nextCodepoint(s: []const u8, i: *usize) u32 {
    const b0 = s[i.*];
    const len: usize = if (b0 < 0x80) 1 else if (b0 & 0xe0 == 0xc0) 2 else if (b0 & 0xf0 == 0xe0) 3 else if (b0 & 0xf8 == 0xf0) 4 else 0;
    if (len == 0 or i.* + len > s.len) {
        i.* += 1;
        return 0xfffd;
    }
    var cp: u32 = if (len == 1) b0 else @as(u32, b0) & (@as(u32, 0x7f) >> @intCast(len));
    for (1..len) |k| {
        const b = s[i.* + k];
        if (b & 0xc0 != 0x80) {
            i.* += 1;
            return 0xfffd;
        }
        cp = (cp << 6) | (b & 0x3f);
    }
    i.* += len;
    return cp;
}

fn textWidth(font: *c.fcft_font, s: []const u8) i32 {
    var w: i32 = 0;
    var i: usize = 0;
    while (i < s.len) {
        const g = c.fcft_rasterize_char_utf32(font, nextCodepoint(s, &i), c.FCFT_SUBPIXEL_NONE) orelse continue;
        w += g.*.advance.x;
    }
    return w;
}

const Painter = struct {
    img: *c.pixman_image_t,
    height: i32,

    fn fill(self: Painter, x: i32, w: i32, color: u24) void {
        if (w <= 0) return;
        const col = rgb(color);
        const rect = c.pixman_rectangle16_t{
            .x = @intCast(x),
            .y = 0,
            .width = @intCast(w),
            .height = @intCast(self.height),
        };
        _ = c.pixman_image_fill_rectangles(c.PIXMAN_OP_SRC, self.img, &col, 1, &rect);
    }

    /// Draws `s` starting at `x`, stopping before any glyph that would cross `max_x`.
    /// Returns the x position after the last drawn glyph.
    fn text(self: Painter, font: *c.fcft_font, s: []const u8, x_start: i32, max_x: i32, color: u24) i32 {
        const col = rgb(color);
        const fg = c.pixman_image_create_solid_fill(&col) orelse return x_start;
        defer _ = c.pixman_image_unref(fg);
        const baseline = @divTrunc(self.height - font.height, 2) + font.ascent;
        var x = x_start;
        var i: usize = 0;
        while (i < s.len) {
            const g = c.fcft_rasterize_char_utf32(font, nextCodepoint(s, &i), c.FCFT_SUBPIXEL_NONE) orelse continue;
            if (x + g.*.advance.x > max_x) break;
            if (c.pixman_image_get_format(g.*.pix) == c.PIXMAN_a8r8g8b8) {
                c.pixman_image_composite32(c.PIXMAN_OP_OVER, g.*.pix, null, self.img, 0, 0, 0, 0, x + g.*.x, baseline - g.*.y, g.*.width, g.*.height);
            } else {
                c.pixman_image_composite32(c.PIXMAN_OP_OVER, fg, g.*.pix, self.img, 0, 0, 0, 0, x + g.*.x, baseline - g.*.y, g.*.width, g.*.height);
            }
            x += g.*.advance.x;
        }
        return x;
    }
};

const Segment = struct { text: []const u8, color: u24, bold: bool = false };

fn bufferRelease(_: ?*anyopaque, buffer: ?*c.wl_buffer) callconv(.c) void {
    c.wl_buffer_destroy(buffer);
}
const buffer_listener = c.wl_buffer_listener{ .release = bufferRelease };

fn loadFonts(bar: *Bar) void {
    if (bar.font) |f| c.fcft_destroy(f);
    if (bar.font_bold) |f| c.fcft_destroy(f);
    var attrs: [64]u8 = undefined;
    var names = font_names;
    const regular = std.fmt.bufPrintSentinel(&attrs, "pixelsize={d}", .{font_px * bar.scale}, 0) catch unreachable;
    bar.font = c.fcft_from_name(names.len, @ptrCast(&names), regular.ptr);
    const bold = std.fmt.bufPrintSentinel(&attrs, "weight=bold:pixelsize={d}", .{font_px * bar.scale}, 0) catch unreachable;
    bar.font_bold = c.fcft_from_name(names.len, @ptrCast(&names), bold.ptr);
    if (bar.font_bold == null) bar.font_bold = bar.font;
}

fn render(bar: *Bar) void {
    bar.dirty = false;
    if (!bar.configured or bar.width == 0) return;
    const font = bar.font orelse return;
    const bold = bar.font_bold orelse font;
    const s = bar.scale;

    const w: i32 = @as(i32, @intCast(bar.width)) * s;
    const h: i32 = bar_height * s;
    const stride = w * 4;
    const size: usize = @intCast(stride * h);

    const fd = c.memfd_create("ripbar", c.MFD_CLOEXEC);
    if (fd < 0) return;
    defer _ = c.close(fd);
    if (c.ftruncate(fd, @intCast(size)) < 0) return;
    const map = c.mmap(null, size, c.PROT_READ | c.PROT_WRITE, c.MAP_SHARED, fd, 0);
    if (map == null or @intFromPtr(map) == std.math.maxInt(usize)) return;
    defer _ = c.munmap(map, size);

    const pool = c.wl_shm_create_pool(shm, fd, @intCast(size));
    const buffer = c.wl_shm_pool_create_buffer(pool, 0, w, h, stride, c.WL_SHM_FORMAT_ARGB8888);
    c.wl_shm_pool_destroy(pool);
    _ = c.wl_buffer_add_listener(buffer, &buffer_listener, null);

    const img = c.pixman_image_create_bits(c.PIXMAN_a8r8g8b8, w, h, @ptrCast(@alignCast(map)), stride) orelse return;
    defer _ = c.pixman_image_unref(img);
    const p = Painter{ .img = img, .height = h };
    p.fill(0, w, col_bg);

    // Tags
    var x: i32 = 0;
    for (0..tag_count) |i| {
        const mask = @as(u32, 1) << @intCast(i);
        const label = [1]u8{'1' + @as(u8, @intCast(i))};
        const focused = bar.focused_tags & mask != 0;
        const occupied = bar.occupied_tags & mask != 0;
        const urgent = bar.urgent_tags & mask != 0;
        const f = if (focused or occupied) bold else font;
        const cell = textWidth(f, &label) + 2 * tag_pad * s;
        if (urgent) p.fill(x, cell, col_urgent) else if (focused) p.fill(x, cell, col_accent);
        _ = p.text(f, &label, x + tag_pad * s, w, if (focused or occupied or urgent) col_bright else col_dim);
        x += cell;
    }

    // Right-hand status, laid out right to left
    var segs_buf: [12]Segment = undefined;
    var segs: std.ArrayList(Segment) = .initBuffer(&segs_buf);
    segs.appendAssumeCapacity(.{ .text = "[Mem: ", .color = col_label });
    segs.appendAssumeCapacity(.{ .text = mem, .color = col_bright, .bold = true });
    segs.appendAssumeCapacity(.{ .text = "] [Vol: ", .color = col_label });
    segs.appendAssumeCapacity(.{ .text = vol, .color = col_bright, .bold = true });
    segs.appendAssumeCapacity(.{ .text = "] ", .color = col_label });
    if (media.len > 0) {
        segs.appendAssumeCapacity(.{ .text = "[", .color = col_media });
        segs.appendAssumeCapacity(.{ .text = media, .color = col_media });
        segs.appendAssumeCapacity(.{ .text = "] ", .color = col_media });
    }
    segs.appendAssumeCapacity(.{ .text = "[", .color = col_date });
    segs.appendAssumeCapacity(.{ .text = date, .color = col_date });
    segs.appendAssumeCapacity(.{ .text = "]", .color = col_date });

    var right_w: i32 = 0;
    for (segs.items) |seg| right_w += textWidth(if (seg.bold) bold else font, seg.text);
    const right_x = @max(x, w - right_w - right_pad * s);
    var rx = right_x;
    for (segs.items) |seg| rx = p.text(if (seg.bold) bold else font, seg.text, rx, w, seg.color);

    // Focused window title, only on the focused output
    if (bar.output == focused_output and title.len > 0) {
        const box_x = x + title_gap * s;
        const max_x = right_x - title_gap * s;
        const text_w = @min(textWidth(font, title), max_x - box_x - 2 * title_pad * s);
        if (text_w > 0) {
            p.fill(box_x, text_w + 2 * title_pad * s, col_accent);
            _ = p.text(font, title, box_x + title_pad * s, box_x + title_pad * s + text_w, col_bright);
        }
    }

    c.wl_surface_set_buffer_scale(bar.surface, s);
    c.wl_surface_attach(bar.surface, buffer, 0, 0);
    c.wl_surface_damage_buffer(bar.surface, 0, 0, w, h);
    c.wl_surface_commit(bar.surface);
}

// ---------------------------------------------------------------------------
// Bars
// ---------------------------------------------------------------------------

fn layerConfigure(data: ?*anyopaque, ls: ?*c.zwlr_layer_surface_v1, serial: u32, width: u32, _: u32) callconv(.c) void {
    const bar: *Bar = @ptrCast(@alignCast(data));
    c.zwlr_layer_surface_v1_ack_configure(ls, serial);
    bar.width = width;
    bar.configured = true;
    bar.dirty = true;
}

fn layerClosed(data: ?*anyopaque, _: ?*c.zwlr_layer_surface_v1) callconv(.c) void {
    destroyBar(@ptrCast(@alignCast(data)));
}

const layer_listener = c.zwlr_layer_surface_v1_listener{ .configure = layerConfigure, .closed = layerClosed };

fn outputFocusedTags(data: ?*anyopaque, _: ?*c.zriver_output_status_v1, tags: u32) callconv(.c) void {
    const bar: *Bar = @ptrCast(@alignCast(data));
    bar.focused_tags = tags;
    bar.dirty = true;
}

fn outputViewTags(data: ?*anyopaque, _: ?*c.zriver_output_status_v1, tags: [*c]c.wl_array) callconv(.c) void {
    const bar: *Bar = @ptrCast(@alignCast(data));
    const words: [*]const u32 = @ptrCast(@alignCast(tags.*.data orelse return));
    bar.occupied_tags = 0;
    for (words[0 .. tags.*.size / 4]) |t| bar.occupied_tags |= t;
    bar.dirty = true;
}

fn outputUrgentTags(data: ?*anyopaque, _: ?*c.zriver_output_status_v1, tags: u32) callconv(.c) void {
    const bar: *Bar = @ptrCast(@alignCast(data));
    bar.urgent_tags = tags;
    bar.dirty = true;
}

fn outputLayoutName(_: ?*anyopaque, _: ?*c.zriver_output_status_v1, _: [*c]const u8) callconv(.c) void {}
fn outputLayoutNameClear(_: ?*anyopaque, _: ?*c.zriver_output_status_v1) callconv(.c) void {}

const output_status_listener = c.zriver_output_status_v1_listener{
    .focused_tags = outputFocusedTags,
    .view_tags = outputViewTags,
    .urgent_tags = outputUrgentTags,
    .layout_name = outputLayoutName,
    .layout_name_clear = outputLayoutNameClear,
};

fn wlOutputGeometry(_: ?*anyopaque, _: ?*c.wl_output, _: i32, _: i32, _: i32, _: i32, _: i32, _: [*c]const u8, _: [*c]const u8, _: i32) callconv(.c) void {}
fn wlOutputMode(_: ?*anyopaque, _: ?*c.wl_output, _: u32, _: i32, _: i32, _: i32) callconv(.c) void {}
fn wlOutputName(_: ?*anyopaque, _: ?*c.wl_output, _: [*c]const u8) callconv(.c) void {}
fn wlOutputDescription(_: ?*anyopaque, _: ?*c.wl_output, _: [*c]const u8) callconv(.c) void {}

fn wlOutputScale(data: ?*anyopaque, _: ?*c.wl_output, factor: i32) callconv(.c) void {
    const bar: *Bar = @ptrCast(@alignCast(data));
    bar.pending_scale = @max(factor, 1);
}

fn wlOutputDone(data: ?*anyopaque, _: ?*c.wl_output) callconv(.c) void {
    const bar: *Bar = @ptrCast(@alignCast(data));
    if (bar.font == null or bar.pending_scale != bar.scale) {
        bar.scale = bar.pending_scale;
        loadFonts(bar);
    }
    bar.dirty = true;
}

const wl_output_listener = c.wl_output_listener{
    .geometry = wlOutputGeometry,
    .mode = wlOutputMode,
    .done = wlOutputDone,
    .scale = wlOutputScale,
    .name = wlOutputName,
    .description = wlOutputDescription,
};

fn setupBar(bar: *Bar) void {
    if (bar.surface != null) return;
    if (bar.font == null) loadFonts(bar);
    bar.surface = c.wl_compositor_create_surface(compositor);
    bar.layer_surface = c.zwlr_layer_shell_v1_get_layer_surface(
        layer_shell,
        bar.surface,
        bar.output,
        c.ZWLR_LAYER_SHELL_V1_LAYER_TOP,
        "ripbar",
    );
    _ = c.zwlr_layer_surface_v1_add_listener(bar.layer_surface, &layer_listener, bar);
    c.zwlr_layer_surface_v1_set_size(bar.layer_surface, 0, bar_height);
    c.zwlr_layer_surface_v1_set_anchor(
        bar.layer_surface,
        c.ZWLR_LAYER_SURFACE_V1_ANCHOR_TOP | c.ZWLR_LAYER_SURFACE_V1_ANCHOR_LEFT | c.ZWLR_LAYER_SURFACE_V1_ANCHOR_RIGHT,
    );
    c.zwlr_layer_surface_v1_set_exclusive_zone(bar.layer_surface, bar_height);
    c.wl_surface_commit(bar.surface);

    bar.status = c.zriver_status_manager_v1_get_river_output_status(status_manager, bar.output);
    _ = c.zriver_output_status_v1_add_listener(bar.status, &output_status_listener, bar);
}

fn destroyBar(bar: *Bar) void {
    for (&bars) |*slot| if (slot.* == bar) {
        slot.* = null;
    };
    if (bar.status) |s| c.zriver_output_status_v1_destroy(s);
    if (bar.layer_surface) |ls| c.zwlr_layer_surface_v1_destroy(ls);
    if (bar.surface) |s| c.wl_surface_destroy(s);
    if (bar.font_bold) |f| if (bar.font_bold != bar.font) c.fcft_destroy(f);
    if (bar.font) |f| c.fcft_destroy(f);
    if (focused_output == bar.output) focused_output = null;
    c.wl_output_destroy(bar.output);
    std.heap.c_allocator.destroy(bar);
}

// ---------------------------------------------------------------------------
// Seat status
// ---------------------------------------------------------------------------

fn seatFocusedOutput(_: ?*anyopaque, _: ?*c.zriver_seat_status_v1, output: ?*c.wl_output) callconv(.c) void {
    focused_output = output;
    markAllDirty();
}

fn seatUnfocusedOutput(_: ?*anyopaque, _: ?*c.zriver_seat_status_v1, output: ?*c.wl_output) callconv(.c) void {
    if (focused_output == output) focused_output = null;
    markAllDirty();
}

fn seatFocusedView(_: ?*anyopaque, _: ?*c.zriver_seat_status_v1, t: [*c]const u8) callconv(.c) void {
    const src = std.mem.span(t);
    const n = @min(src.len, title_buf.len);
    @memcpy(title_buf[0..n], src[0..n]);
    title = title_buf[0..n];
    markAllDirty();
}

fn seatMode(_: ?*anyopaque, _: ?*c.zriver_seat_status_v1, _: [*c]const u8) callconv(.c) void {}

const seat_status_listener = c.zriver_seat_status_v1_listener{
    .focused_output = seatFocusedOutput,
    .unfocused_output = seatUnfocusedOutput,
    .focused_view = seatFocusedView,
    .mode = seatMode,
};

// ---------------------------------------------------------------------------
// Registry
// ---------------------------------------------------------------------------

fn bind(registry: ?*c.wl_registry, name: u32, iface: *const c.wl_interface, version: u32, max: u32) ?*anyopaque {
    return c.wl_registry_bind(registry, name, iface, @min(version, max));
}

fn registryGlobal(_: ?*anyopaque, registry: ?*c.wl_registry, name: u32, iface_c: [*c]const u8, version: u32) callconv(.c) void {
    const iface = std.mem.span(iface_c);
    if (std.mem.eql(u8, iface, std.mem.span(c.wl_compositor_interface.name))) {
        compositor = @ptrCast(bind(registry, name, &c.wl_compositor_interface, version, 4));
    } else if (std.mem.eql(u8, iface, std.mem.span(c.wl_shm_interface.name))) {
        shm = @ptrCast(bind(registry, name, &c.wl_shm_interface, version, 1));
    } else if (std.mem.eql(u8, iface, std.mem.span(c.zwlr_layer_shell_v1_interface.name))) {
        layer_shell = @ptrCast(bind(registry, name, &c.zwlr_layer_shell_v1_interface, version, 4));
    } else if (std.mem.eql(u8, iface, std.mem.span(c.zriver_status_manager_v1_interface.name))) {
        status_manager = @ptrCast(bind(registry, name, &c.zriver_status_manager_v1_interface, version, 4));
    } else if (std.mem.eql(u8, iface, std.mem.span(c.wl_seat_interface.name))) {
        if (seat == null) seat = @ptrCast(bind(registry, name, &c.wl_seat_interface, version, 1));
    } else if (std.mem.eql(u8, iface, std.mem.span(c.wl_output_interface.name))) {
        const output: *c.wl_output = @ptrCast(bind(registry, name, &c.wl_output_interface, version, 4) orelse return);
        const bar = std.heap.c_allocator.create(Bar) catch return;
        bar.* = .{ .output = output, .global_name = name };
        _ = c.wl_output_add_listener(output, &wl_output_listener, bar);
        for (&bars) |*slot| {
            if (slot.* == null) {
                slot.* = bar;
                break;
            }
        } else {
            destroyBar(bar);
            return;
        }
        if (initialized) setupBar(bar);
    }
}

fn registryGlobalRemove(_: ?*anyopaque, _: ?*c.wl_registry, name: u32) callconv(.c) void {
    for (bars) |maybe| if (maybe) |bar| if (bar.global_name == name) {
        destroyBar(bar);
        return;
    };
}

const registry_listener = c.wl_registry_listener{ .global = registryGlobal, .global_remove = registryGlobalRemove };

// ---------------------------------------------------------------------------
// Main loop
// ---------------------------------------------------------------------------

fn die(msg: []const u8) noreturn {
    std.debug.print("ripbar: {s}\n", .{msg});
    std.process.exit(1);
}

pub fn main() void {
    _ = c.fcft_init(c.FCFT_LOG_COLORIZE_AUTO, false, c.FCFT_LOG_CLASS_ERROR);

    display = c.wl_display_connect(null) orelse die("cannot connect to Wayland display");
    const registry = c.wl_display_get_registry(display);
    _ = c.wl_registry_add_listener(registry, &registry_listener, null);
    if (c.wl_display_roundtrip(display) < 0) die("initial roundtrip failed");

    if (compositor == null or shm == null) die("compositor lacks wl_compositor or wl_shm");
    if (layer_shell == null) die("compositor lacks wlr-layer-shell");
    if (status_manager == null) die("compositor lacks river-status (is this river 0.3.x?)");

    // Output scale arrives in this roundtrip, so fonts load at the right size.
    _ = c.wl_display_roundtrip(display);
    initialized = true;
    for (bars) |maybe| if (maybe) |bar| setupBar(bar);
    if (seat) |s| {
        seat_status = c.zriver_status_manager_v1_get_river_seat_status(status_manager, s);
        _ = c.zriver_seat_status_v1_add_listener(seat_status, &seat_status_listener, null);
    }

    // Tick on each wall-clock second so the seconds display stays in step.
    const timer = c.timerfd_create(c.CLOCK_REALTIME, c.TFD_CLOEXEC);
    if (timer < 0) die("timerfd_create failed");
    var now: c.struct_timespec = undefined;
    _ = c.clock_gettime(c.CLOCK_REALTIME, &now);
    const spec = c.struct_itimerspec{
        .it_interval = .{ .tv_sec = 1, .tv_nsec = 0 },
        .it_value = .{ .tv_sec = now.tv_sec + 1, .tv_nsec = 0 },
    };
    _ = c.timerfd_settime(timer, c.TFD_TIMER_ABSTIME, &spec, null);
    updateStatus();

    var fds = [2]c.struct_pollfd{
        .{ .fd = c.wl_display_get_fd(display), .events = c.POLLIN, .revents = 0 },
        .{ .fd = timer, .events = c.POLLIN, .revents = 0 },
    };

    while (true) {
        for (bars) |maybe| if (maybe) |bar| if (bar.dirty) render(bar);

        while (c.wl_display_prepare_read(display) != 0) {
            if (c.wl_display_dispatch_pending(display) < 0) die("lost connection to compositor");
        }
        _ = c.wl_display_flush(display);

        if (c.poll(&fds, fds.len, -1) < 0) {
            c.wl_display_cancel_read(display);
            continue;
        }

        if (fds[0].revents & c.POLLIN != 0) {
            if (c.wl_display_read_events(display) < 0) die("lost connection to compositor");
        } else {
            c.wl_display_cancel_read(display);
        }
        if (fds[0].revents & (c.POLLHUP | c.POLLERR) != 0) die("lost connection to compositor");
        if (c.wl_display_dispatch_pending(display) < 0) die("lost connection to compositor");

        if (fds[1].revents & c.POLLIN != 0) {
            var expirations: u64 = 0;
            _ = c.read(timer, &expirations, @sizeOf(u64));
            updateStatus();
        }
    }
}
