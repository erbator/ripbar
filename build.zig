const std = @import("std");

const protocols = [_][]const u8{
    "protocol/river-status-unstable-v1.xml",
    "protocol/wlr-layer-shell-unstable-v1.xml",
    "/usr/share/wayland-protocols/stable/xdg-shell/xdg-shell.xml",
    "/usr/share/wayland-protocols/stable/viewporter/viewporter.xml",
    "/usr/share/wayland-protocols/staging/fractional-scale/fractional-scale-v1.xml",
};

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    const translate = b.addTranslateC(.{
        .root_source_file = b.path("src/c.h"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    translate.addSystemIncludePath(.{ .cwd_relative = "/usr/include/pixman-1" });

    for (protocols) |xml| {
        const xml_path: std.Build.LazyPath = if (std.fs.path.isAbsolute(xml))
            .{ .cwd_relative = xml }
        else
            b.path(xml);
        const name = std.fs.path.stem(xml);

        const header = b.addSystemCommand(&.{ "wayland-scanner", "client-header" });
        header.addFileArg(xml_path);
        const h = header.addOutputFileArg(b.fmt("{s}-client-protocol.h", .{name}));

        const code = b.addSystemCommand(&.{ "wayland-scanner", "private-code" });
        code.addFileArg(xml_path);
        const c_file = code.addOutputFileArg(b.fmt("{s}-protocol.c", .{name}));

        translate.addIncludePath(h.dirname());
        exe_mod.addIncludePath(h.dirname());
        exe_mod.addCSourceFile(.{ .file = c_file });
    }

    exe_mod.addImport("c", translate.createModule());
    exe_mod.linkSystemLibrary("wayland-client", .{});
    exe_mod.linkSystemLibrary("fcft", .{ .use_pkg_config = .no });
    exe_mod.linkSystemLibrary("pixman-1", .{});

    const exe = b.addExecutable(.{ .name = "ripbar", .root_module = exe_mod });
    b.installArtifact(exe);

    const run = b.addRunArtifact(exe);
    run.step.dependOn(b.getInstallStep());
    b.step("run", "Run the bar").dependOn(&run.step);
}
