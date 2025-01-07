const std = @import("std");

const raylib = @import("raylib");
const raygui = @import("raygui");

const App = @import("App.zig");
const SaveManager = @import("SaveManager.zig");

pub const NodeType = enum {
    NONE,
    SYSTEM,
    PLAYER_ACTION,
    SFX_VFX,
    CODE,
    DIALOGUE,
    UI,
    NOTE,
};

const NodeData = struct { // FOR JSON CONVERSION & PARSING
    id: u32,
    parent: u32,
    children: []u32,
    conditions: []u32,
    content: []u8,
    type: NodeType,
};

const Node = @This();
id: usize,
content: std.ArrayList(u8),
parent: *Node,
children: std.ArrayList(*Node),
conditions: std.ArrayList(*Node),

children_width: usize,
depth: usize,
sibling_order: usize,
actual_x: usize,
type: NodeType,

pub fn init(alloc: std.mem.Allocator, id: usize) !*Node {
    const node = try alloc.create(Node);
    errdefer alloc.destroy(node);

    const _content = std.ArrayList(u8).init(alloc);
    const _children = std.ArrayList(*Node).init(alloc);
    const _conditions = std.ArrayList(*Node).init(alloc);

    node.* = .{
        .id = id,
        .content = _content,
        .parent = undefined,
        .children = _children,
        .conditions = _conditions,
        .children_width = 0,
        .depth = 0,
        .sibling_order = 0,
        .actual_x = 0,
        .type = NodeType.NONE,
    };

    return node;
}

pub fn deinit(self: *Node, alloc: std.mem.Allocator) void {
    for (self.children.items) |child| {
        child.deinit(alloc);
        alloc.destroy(child);
    }
    self.children.deinit();
    self.conditions.deinit();
    self.content.deinit();
}

pub fn deinit_child(self: *Node, id: usize, alloc: std.mem.Allocator) void {
    self.children.items[id].solo_deinit();
    alloc.destroy(self.children.items[id]);
    _ = self.children.orderedRemove(id);
}

pub fn solo_deinit(self: *Node) void {
    self.children.deinit();
    self.conditions.deinit();
    self.content.deinit();
}

pub fn free_recursive(self: *Node, alloc: std.mem.Allocator) void {
    // Free content array
    self.content.deinit();

    // Free conditions array
    self.conditions.deinit();

    // Recursively free child nodes
    for (self.children.items) |child| {
        child.*.free_recursive(alloc);
    }

    // Free children array
    self.children.deinit();

    // Finally, free the node itself
    alloc.destroy(self);
}

pub fn compute_children_order(self: *Node) void {
    for (self.children.items, 0..) |child, i| {
        child.sibling_order = i;
        child.compute_children_order();
        //std.log.debug("TREE : {} {}", .{ child.id, child.sibling_order });
    }
}

pub fn compute_children_depth(self: *Node, depth: usize) void {
    self.depth = depth;
    for (self.children.items) |child| {
        child.compute_children_depth(depth + 1);
    }
}

pub fn add_parent(self: *Node, parent: *Node) void {
    self.parent = parent;
}

pub fn add_child(self: *Node, child: *Node) void {
    child.depth = self.depth + 1;
    child.sibling_order = self.children.items.len;
    self.children.append(child) catch unreachable;
}

pub fn add_condition(self: *Node, condition: *Node) void {
    self.conditions.append(condition) catch unreachable;
}

pub fn new_content(self: *Node, content: []const u8) void {
    for (self.content.items) |car| {
        _ = car;
        _ = self.content.pop();
    }
    for (content) |car| {
        if (self.content.append(car)) |stmt| {
            _ = stmt;
        } else |e| {
            std.log.debug("{any}", .{e});
        }
    }
    if (self.content.append(0)) |stmt| {
        _ = stmt;
    } else |e| {
        std.log.debug("{any}", .{e});
    }
}

pub fn evaluate_offset(self: *Node, offset: usize) usize {
    self.actual_x = offset;
    //std.log.debug("{}, {}", .{ self.id, self.offset });
    var temp_offset: usize = offset;
    var i: usize = 0;
    while (i != self.children.items.len) {
        if (i != 0) {
            temp_offset = self.children.items[i].evaluate_offset(temp_offset + 1);
        } else {
            temp_offset = self.children.items[i].evaluate_offset(temp_offset + 0);
        }
        i += 1;
    }
    return temp_offset;
}

pub fn render(self: *Node, settings: App.AppSettings) void {
    self.render_dummy(settings);
}

pub fn render_dummy(self: *Node, settings: App.AppSettings) void {
    var bounds = raylib.Rectangle{
        .x = @as(f32, @floatFromInt(self.depth)) * @as(f32, @floatFromInt(settings.node_size_x + settings.node_gap_x)),
        .y = @as(f32, @floatFromInt(self.actual_x)) * @as(f32, @floatFromInt(settings.node_size_y + settings.node_gap_y)),
        .width = @as(f32, @floatFromInt(settings.node_size_x)),
        .height = @as(f32, @floatFromInt(settings.node_size_y)),
    };

    raylib.drawRectangleRounded(bounds, 0.15, 2, self.get_node_color());
    //raylib.drawRectangleRoundedLines(rec: Rectangle, roundness: f32, segments: i32, color: Color)
    _ = raylib.drawText(self.get_node_string_type(), @intFromFloat(bounds.x + 8), @intFromFloat(bounds.y + 8), 10, raylib.Color.black);

    bounds.y += 24;
    bounds.height -= 24;

    raylib.drawRectangleRounded(bounds, 0.1, 2, raylib.Color.white);

    bounds.x += 5;
    bounds.width -= 10;

    if (self.content.items.len != 0) {
        _ = raygui.guiLabel(bounds, self.content.items[0 .. self.content.items.len - 1 :0]);
    }

    bounds.x -= 5;
    bounds.width += 10;

    for (self.children.items) |child| {
        child.render(settings);
        const vec_start = raylib.Vector2{
            .x = bounds.x + @as(f32, @floatFromInt(settings.node_size_x)),
            .y = bounds.y + @as(f32, @floatFromInt(@divTrunc(settings.node_size_y, 2) - 24)),
        };
        const vec_end = raylib.Vector2{
            .x = @as(f32, (@floatFromInt(child.depth))) * @as(f32, @floatFromInt(settings.node_size_x + settings.node_gap_x)),
            .y = @as(f32, @floatFromInt(child.actual_x)) * @as(f32, @floatFromInt((settings.node_size_y + settings.node_gap_y))) + @as(f32, @floatFromInt(@divTrunc(settings.node_size_y, 2))),
        };
        const points = [_]raylib.Vector2{ vec_start, raylib.Vector2{ .x = vec_start.x + 10.0, .y = vec_start.y }, raylib.Vector2{ .x = vec_end.x - 10.0, .y = vec_end.y }, vec_end };
        raylib.drawSplineBezierCubic(&points, settings.link_thickness, raylib.Color.black);
    }
}

pub fn get_node_color(self: *Node) raylib.Color {
    var color = raylib.Color.init(0, 0, 0, 0);

    switch (self.type) {
        .NONE => {
            color = raylib.Color.init(220, 220, 220, 255);
        },
        .SYSTEM => {
            color = raylib.Color.init(123, 194, 61, 255);
        },
        .PLAYER_ACTION => {
            color = raylib.Color.init(82, 169, 206, 255);
        },
        .SFX_VFX => {
            color = raylib.Color.init(170, 95, 160, 255);
        },
        .CODE => {
            color = raylib.Color.init(80, 70, 183, 255);
        },
        .DIALOGUE => {
            color = raylib.Color.init(240, 166, 202, 255);
        },
        .UI => {
            color = raylib.Color.init(150, 150, 150, 255);
        },
        .NOTE => {
            color = raylib.Color.init(238, 243, 106, 255);
        },
    }
    return color;
}

pub fn get_node_string_type(self: *Node) [:0]const u8 {
    var text: [:0]const u8 = undefined;

    switch (self.type) {
        .NONE => {
            text = "Node";
        },
        .SYSTEM => {
            text = "System";
        },
        .PLAYER_ACTION => {
            text = "Player Action";
        },
        .SFX_VFX => {
            text = "SFX/VFX";
        },
        .CODE => {
            text = "Code";
        },
        .DIALOGUE => {
            text = "Dialogue";
        },
        .UI => {
            text = "UI";
        },
        .NOTE => {
            text = "Note";
        },
    }
    return text;
}
