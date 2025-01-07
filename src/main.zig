const std = @import("std");

const raylib = @import("raylib");
const raygui = @import("raygui");

const App = @import("App.zig");
const Story = @import("Story.zig");
const SaveManager = @import("SaveManager.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer {
        const deinit_status = gpa.deinit();
        if (deinit_status == .leak) std.testing.expect(false) catch @panic("MEMORY LEAK");
    }

    const _camera = try allocator.create(raylib.Camera2D);
    _camera.* = .{ .offset = undefined, .rotation = undefined, .target = undefined, .zoom = undefined };

    defer {
        allocator.destroy(_camera);
    }

    var _story = try Story.init(allocator);
    defer {
        _story.deinit(allocator);
        allocator.destroy(_story);
    }

    const _save_manager = try SaveManager.init(allocator);
    defer {
        _save_manager.deinit(allocator);
        allocator.destroy(_save_manager);
    }

    const _app = try App.init(allocator, _story, _camera, _save_manager);
    defer {
        _app.deinit();
        allocator.destroy(_app);
    }

    const main_loop_thread = try std.Thread.spawn(.{}, main_loop, .{_app});
    main_loop_thread.join();
}

pub fn main_loop(app: *App) !void {
    const flags = raylib.ConfigFlags{ .window_resizable = true };
    raylib.setConfigFlags(flags);
    raylib.initWindow(800, 500, "storyflow");
    //raylib.setWindowMonitor(1);
    //raylib.maximizeWindow();

    const img = raylib.genImageChecked(50, 50, 25, 25, raylib.Color{ .r = 120, .g = 120, .b = 120, .a = 255 }, raylib.Color.gray);
    const background = raylib.loadTextureFromImage(img);
    raylib.unloadImage(img);

    app.update_camera();

    raylib.setTargetFPS(140);

    var windowOpen = true;

    while (windowOpen) {
        {
            try app.update();
        }
        {
            raylib.beginDrawing();
            raylib.clearBackground(raylib.Color.dark_gray);

            //raylib.drawRectangle(0, @divTrunc(raylib.getScreenHeight(), 2) - 2, raylib.getScreenWidth(), 5, raylib.Color.gray);

            raylib.beginMode2D(app.refs.camera.*);

            const rec = raylib.Rectangle{ .x = app.refs.camera.target.x - app.refs.camera.offset.x, .y = app.refs.camera.target.y - app.refs.camera.offset.y, .width = @as(f32, @floatFromInt(raylib.getScreenWidth())) / app.refs.camera.zoom, .height = @as(f32, @floatFromInt(raylib.getScreenHeight())) / app.refs.camera.zoom };
            raylib.drawTexturePro(background, rec, rec, raylib.Vector2.zero(), 0, raylib.Color.white);

            raylib.endMode2D();

            if (app.refs.story.next_available_id != 0) {
                const bounds = raylib.Rectangle{
                    .x = @floatFromInt(@divTrunc(raylib.getScreenWidth(), 2) - @divTrunc(app.settings.node_size_x, 2) + 3),
                    .y = @floatFromInt(@divTrunc(raylib.getScreenHeight(), 2) - @divTrunc(app.settings.node_size_y, 2) + 3),
                    .width = @floatFromInt(app.settings.node_size_x),
                    .height = @floatFromInt(app.settings.node_size_y),
                };
                raylib.drawRectangleRounded(bounds, 0.15, 4, raylib.Color.blue);
            }

            raylib.beginMode2D(app.refs.camera.*);

            app.render();

            raylib.endMode2D();

            app.render_ui();

            //raylib.drawFPS(10, 10);
            raylib.endDrawing();
        }

        if (raylib.isKeyPressed(raylib.KeyboardKey.key_escape)) {
            while (app.refs.story.saved == false and app.refs.story.has_current_node()) {
                raylib.beginDrawing();

                const bounds = raylib.Rectangle{ .x = 100, .y = 100, .width = 350, .height = 120 };

                const result = raygui.guiMessageBox(bounds, "You forgot to save!", "If you don't sasve, all progress will be lost", "SAVE;CLOSE WITHOUT SAVING");

                if (result == 1) {
                    try app.refs.save_manager.write_to_save(app.refs.story.root, app.refs.alloc);
                    app.refs.story.saved = true;
                    break;
                } else if (result == 2) {
                    windowOpen = false;
                    break;
                } else if (result == 0) {
                    break;
                }
                raylib.endDrawing();
            }
            if (app.refs.story.saved or !app.refs.story.has_current_node()) {
                windowOpen = false;
            }
        }
    }
}
