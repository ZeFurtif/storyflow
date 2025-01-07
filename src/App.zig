const std = @import("std");

const raylib = @import("raylib");
const raygui = @import("raygui");

const Story = @import("Story.zig");
const Node = @import("Node.zig");
const SaveManager = @import("SaveManager.zig");

pub const AppRefs = struct {
    alloc: std.mem.Allocator,
    story: *Story,
    camera: *raylib.Camera2D,
    save_manager: *SaveManager,
};

pub const AppSettings = struct {
    node_size_x: i32,
    node_size_y: i32,
    node_gap_x: i32,
    node_gap_y: i32,
    link_thickness: f32,
};

const InputType = enum {
    NONE,
    SAVE,
    OPEN,
    MOVE_UP,
    MOVE_DOWN,
    MOVE_NEXT_SIBLING,
    MOVE_PREV_SIBLING,
    REARANGE_UP,
    REARANGE_DOWN,
    NEW_NODE,
    DELETE_NODE,
    INSERT_PARENT_NODE,
    INSERT_CHILD_NODE,
    TOGGLE_RENAME,
    TOGGLE_SEARCH,
    MAKE_SYSTEM,
    MAKE_PLAYER_ACTION,
    MAKE_SFX_VFX,
    MAKE_CODE,
    MAKE_DIALOGUE,
    MAKE_UI,
    MAKE_NOTE,
    MAKE_NONE,
    SHOW_HELP,
};

const App = @This();
refs: AppRefs,
settings: AppSettings,
current_input: InputType,

renaming: bool,
searching: bool,
text_input: std.ArrayList(u8),

show_help: bool,

pub fn init(allocator: std.mem.Allocator, story: *Story, camera: *raylib.Camera2D, save_manager: *SaveManager) !*App {
    const app = try allocator.create(App);

    app.* = .{
        .refs = AppRefs{
            .alloc = allocator,
            .story = story,
            .camera = camera,
            .save_manager = save_manager,
        },
        .settings = AppSettings{
            .node_size_x = 200,
            .node_size_y = 130,
            .node_gap_x = 30,
            .node_gap_y = 30,
            .link_thickness = 2.0,
        },
        .current_input = InputType.NONE,
        .renaming = false,
        .searching = false,
        .text_input = std.ArrayList(u8).init(allocator),
        .show_help = false,
    };

    return app;
}

pub fn deinit(self: *App) void {
    self.text_input.deinit();
}

pub fn update(self: *App) !void {
    if (self.renaming or self.searching) {
        const cur_key: u8 = @intCast(raylib.getCharPressed());
        if ((cur_key >= 32) and (cur_key <= 125)) {
            try self.text_input.append(cur_key);
        }
        if (raylib.isKeyPressed(raylib.KeyboardKey.key_backspace)) {
            if (raylib.isKeyDown(raylib.KeyboardKey.key_left_control)) {
                var i = self.text_input.items.len - 1;
                while (i > 0) {
                    if (self.text_input.items[i] == 32) {
                        break;
                    }
                    _ = self.text_input.pop();
                    if (i != 0) {
                        i -= 1;
                    }
                }
            } else {
                _ = self.text_input.pop();
            }
        }
    }

    self.handle_input();

    if (self.current_input != InputType.NONE) {
        if (self.renaming or self.searching) {
            if (self.current_input == InputType.TOGGLE_RENAME) {
                self.renaming = !self.renaming;
                if (!self.renaming and self.text_input.items.len != 0 and self.refs.story.next_available_id != 0) {
                    try self.text_input.append(0);
                    self.refs.story.current_node_selected.new_content(self.text_input.items[0 .. self.text_input.items.len - 1]);
                    self.clear_input_text();
                }
            }
            if (self.current_input == InputType.TOGGLE_SEARCH) {
                self.searching = !self.searching;
                if (!self.renaming and self.text_input.items.len != 0) { //FIXME : ADD ACTION SEACH DOESN'T WORK NOW
                    //try self.text_input.append(0);
                    //self.refs.story.current_node_selected.new_content(self.text_input.items[0 .. self.text_input.items.len - 1]);
                    self.clear_input_text();
                }
            }
        } else {
            try self.switch_on_input();
        }
    }

    self.update_camera();
}

pub fn handle_input(self: *App) void {
    if (self.current_input != InputType.NONE) {
        self.current_input = InputType.NONE;
        return;
    } else {
        if (raylib.isKeyDown(raylib.KeyboardKey.key_left_control)) { // CTRL + ...
            if (raylib.isKeyPressed(raylib.KeyboardKey.key_s)) {
                self.current_input = InputType.SAVE;
                return;
            }
            if (raylib.isKeyPressed(raylib.KeyboardKey.key_o)) {
                self.current_input = InputType.OPEN;
                return;
            }
            if (raylib.isKeyPressed(raylib.KeyboardKey.key_n)) {
                self.current_input = InputType.NEW_NODE;
                return;
            }
            if (raylib.isKeyPressed(raylib.KeyboardKey.key_q)) {
                self.current_input = InputType.DELETE_NODE;
                return;
            }
            if (raylib.isKeyPressed(raylib.KeyboardKey.key_left)) {
                self.current_input = InputType.INSERT_PARENT_NODE;
                return;
            }
            if (raylib.isKeyPressed(raylib.KeyboardKey.key_right)) {
                self.current_input = InputType.INSERT_CHILD_NODE;
                return;
            }
            if (raylib.isKeyPressed(raylib.KeyboardKey.key_up)) {
                self.current_input = InputType.REARANGE_UP;
                return;
            }
            if (raylib.isKeyPressed(raylib.KeyboardKey.key_down)) {
                self.current_input = InputType.REARANGE_DOWN;
                return;
            }
        }
        if (raylib.isKeyPressed(raylib.KeyboardKey.key_up)) {
            self.current_input = InputType.MOVE_PREV_SIBLING;
            return;
        }
        if (raylib.isKeyPressed(raylib.KeyboardKey.key_down)) {
            self.current_input = InputType.MOVE_NEXT_SIBLING;
            return;
        }
        if (raylib.isKeyPressed(raylib.KeyboardKey.key_left)) {
            self.current_input = InputType.MOVE_UP;
            return;
        }
        if (raylib.isKeyPressed(raylib.KeyboardKey.key_right)) {
            self.current_input = InputType.MOVE_DOWN;
            return;
        }
        if (raylib.isKeyPressed(raylib.KeyboardKey.key_enter)) {
            self.current_input = InputType.TOGGLE_RENAME;
            return;
        }
        if (raylib.isKeyPressed(raylib.KeyboardKey.key_tab)) {
            self.current_input = InputType.TOGGLE_SEARCH;
            return;
        }
        if (raylib.isKeyPressed(raylib.KeyboardKey.key_one)) {
            self.current_input = InputType.MAKE_SYSTEM;
            return;
        }
        if (raylib.isKeyPressed(raylib.KeyboardKey.key_two)) {
            self.current_input = InputType.MAKE_PLAYER_ACTION;
            return;
        }
        if (raylib.isKeyPressed(raylib.KeyboardKey.key_three)) {
            self.current_input = InputType.MAKE_SFX_VFX;
            return;
        }
        if (raylib.isKeyPressed(raylib.KeyboardKey.key_four)) {
            self.current_input = InputType.MAKE_CODE;
            return;
        }
        if (raylib.isKeyPressed(raylib.KeyboardKey.key_five)) {
            self.current_input = InputType.MAKE_DIALOGUE;
            return;
        }
        if (raylib.isKeyPressed(raylib.KeyboardKey.key_six)) {
            self.current_input = InputType.MAKE_UI;
            return;
        }
        if (raylib.isKeyPressed(raylib.KeyboardKey.key_seven)) {
            self.current_input = InputType.MAKE_NOTE;
            return;
        }
        if (raylib.isKeyPressed(raylib.KeyboardKey.key_zero)) {
            self.current_input = InputType.MAKE_NONE;
            return;
        }
        if (raylib.isKeyPressed(raylib.KeyboardKey.key_l)) {
            self.current_input = InputType.SHOW_HELP;
        }
    }
}

pub fn switch_on_input(self: *App) !void {
    if (self.current_input == InputType.NONE) return;

    self.refs.story.saved = false;

    switch (self.current_input) {
        .NEW_NODE => self.refs.story.new_node(self.refs.alloc),
        .DELETE_NODE => try self.refs.story.delete_node(self.refs.alloc),
        .INSERT_PARENT_NODE => try self.refs.story.insert_parent(self.refs.alloc),
        .INSERT_CHILD_NODE => try self.refs.story.insert_child(self.refs.alloc),
        .MOVE_UP => self.refs.story.move_up(),
        .MOVE_DOWN => self.refs.story.move_down(),
        .MOVE_PREV_SIBLING => self.refs.story.move_prev(),
        .MOVE_NEXT_SIBLING => self.refs.story.move_next(),
        .TOGGLE_RENAME => self.renaming = !self.renaming,
        .TOGGLE_SEARCH => self.searching = !self.searching,
        .MAKE_SYSTEM => self.refs.story.current_node_selected.type = Node.NodeType.SYSTEM,
        .MAKE_PLAYER_ACTION => self.refs.story.current_node_selected.type = Node.NodeType.PLAYER_ACTION,
        .MAKE_SFX_VFX => self.refs.story.current_node_selected.type = Node.NodeType.SFX_VFX,
        .MAKE_CODE => self.refs.story.current_node_selected.type = Node.NodeType.CODE,
        .MAKE_DIALOGUE => self.refs.story.current_node_selected.type = Node.NodeType.DIALOGUE,
        .MAKE_UI => self.refs.story.current_node_selected.type = Node.NodeType.UI,
        .MAKE_NOTE => self.refs.story.current_node_selected.type = Node.NodeType.NOTE,
        .MAKE_NONE => self.refs.story.current_node_selected.type = Node.NodeType.NONE,
        .SHOW_HELP => self.show_help = !self.show_help,
        .NONE => unreachable, // We checked for NONE at the start
        .SAVE => if (self.refs.story.has_current_node()) {
            try self.refs.save_manager.write_to_save(self.refs.story.root, self.refs.alloc);
            self.refs.story.saved = true;
        },
        .OPEN => {
            const data = try self.refs.save_manager.read_from_save(self.refs.alloc);
            //std.log.debug("{any}", .{data});
            try self.refs.story.reconstructTree(data.?.*, self.refs.alloc);
            //self.refs.save_manager.loaded_save.deinit(self.refs.alloc);
        },
        .REARANGE_UP => {
            try self.refs.story.rearange_up();
        },
        .REARANGE_DOWN => {
            try self.refs.story.rearange_down();
        },
    }
}

pub fn clear_input_text(self: *App) void {
    for (self.text_input.items) |car| {
        _ = car;
        _ = self.text_input.pop();
    }
}

pub fn update_camera(self: *App) void {
    var target_x: f32 = 0;
    var target_y: f32 = 0;
    if (self.refs.story.next_available_id + self.refs.story.reuse_ids.items.len > 0) {
        target_x = @as(f32, @floatFromInt(self.refs.story.current_node_selected.depth)) * @as(f32, @floatFromInt(self.settings.node_size_x + self.settings.node_gap_x));
        target_y = @as(f32, @floatFromInt(self.refs.story.current_node_selected.actual_x)) * @as(f32, @floatFromInt(self.settings.node_size_y + self.settings.node_gap_y));
    }

    self.refs.camera.* = .{ .offset = raylib.Vector2{
        .x = @floatFromInt(@divTrunc(raylib.getScreenWidth(), 2) - @divTrunc(self.settings.node_size_x, 2)),
        .y = @floatFromInt(@divTrunc(raylib.getScreenHeight(), 2) - @divTrunc(self.settings.node_size_y, 2)),
    }, .rotation = 0.0, .target = raylib.Vector2{ .x = target_x, .y = target_y }, .zoom = 1 };
}

pub fn render(self: *App) void {
    self.refs.story.render(self.settings);
}

pub fn render_ui(self: *App) void {
    if (self.show_help) {
        self.render_help();
    }
    if (self.renaming) {
        self.render_rename();
    }
    if (self.searching) {
        self.render_search();
    }
}

pub fn render_help(self: *App) void {
    _ = self;

    const bounds = raylib.Rectangle{
        .x = @as(f32, @floatFromInt(raylib.getScreenWidth())) - 200,
        .y = 5,
        .width = 190,
        .height = 600,
    };

    raylib.drawRectangleRounded(bounds, 0.1, 2, raylib.Color.light_gray);
}

pub fn render_rename(self: *App) void {
    var buf = [_]u8{undefined} ** 150;
    for (self.text_input.items, 0..) |car, i| {
        if (i >= 150) {
            break;
        }
        buf[i] = car;
    }
    buf[buf.len - 1] = 0;

    const x = @divTrunc(raylib.getScreenWidth(), 2) - 150;
    const y = @divTrunc(raylib.getScreenHeight(), 2);

    raylib.drawRectangle(x, y, 300, 24, raylib.Color.sky_blue);
    raylib.drawText(buf[0 .. buf.len - 1 :0], 2 + x, 2 + y, 20, raylib.Color.white);
}

pub fn render_search(self: *App) void {
    var buf = [_]u8{undefined} ** 150;
    for (self.text_input.items, 0..) |car, i| {
        if (i >= 150) {
            break;
        }
        buf[i] = car;
    }
    buf[buf.len - 1] = 0;

    const x = @divTrunc(raylib.getScreenWidth(), 2) - 150;
    const y = @divTrunc(raylib.getScreenHeight(), 2);

    raylib.drawRectangle(x, y, 300, 24, raylib.Color.lime);
    raylib.drawText(buf[0 .. buf.len - 1 :0], 2 + x, 2 + y, 20, raylib.Color.white);
}
