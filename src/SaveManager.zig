const std = @import("std");
const Node = @import("Node.zig");

pub const SaveData = struct {
    nodes: []NodeData,

    pub fn init(allocator: std.mem.Allocator) !*SaveData {
        const save_data = try allocator.create(SaveData);
        errdefer allocator.destroy(save_data);
        save_data.* = SaveData{
            .nodes = try allocator.alloc(NodeData, 0),
        };

        return save_data;
    }

    pub fn addNode(self: *SaveData, node: NodeData, allocator: std.mem.Allocator) !void {
        const new_nodes = try allocator.realloc(self.nodes, self.nodes.len + 1);
        self.nodes = new_nodes;
        self.nodes[self.nodes.len - 1] = node;
    }
    pub fn clone(self: SaveData, allocator: std.mem.Allocator) !SaveData {
        var cloned_nodes = try allocator.alloc(NodeData, self.nodes.len);
        errdefer allocator.free(cloned_nodes);

        for (self.nodes, 0..) |node, i| {
            cloned_nodes[i] = try node.clone(allocator);
        }

        return SaveData{
            .nodes = cloned_nodes,
        };
    }
    pub fn deinit(self: *SaveData, allocator: std.mem.Allocator) void {
        for (self.nodes) |*node| {
            node.deinit(allocator);
        }
        allocator.free(self.nodes);
    }
};

pub const NodeData = struct {
    id: usize,
    content: []const u8,
    children: []const usize, // Store just the IDs of children
    conditions: []const usize,
    children_width: usize,
    depth: usize,
    sibling_order: usize,
    actual_x: usize,
    type: Node.NodeType,

    pub fn fromNode(node: *const Node, allocator: std.mem.Allocator) !NodeData {
        var children_ids = try allocator.alloc(usize, node.children.items.len);
        errdefer allocator.free(children_ids);
        for (node.children.items, 0..) |child, i| {
            children_ids[i] = child.id;
        }

        var condition_ids = try allocator.alloc(usize, node.conditions.items.len);
        errdefer allocator.free(condition_ids);
        for (node.conditions.items, 0..) |con, i| {
            condition_ids[i] = con.id;
        }

        return NodeData{
            .id = node.id,
            .content = try allocator.dupe(u8, node.content.items),
            .children = children_ids,
            .conditions = condition_ids,
            .children_width = node.children_width,
            .depth = node.depth,
            .sibling_order = node.sibling_order,
            .actual_x = node.actual_x,
            .type = node.type,
        };
    }

    pub fn clone(self: NodeData, allocator: std.mem.Allocator) !NodeData {
        const cloned_content = try allocator.dupe(u8, self.content);
        errdefer allocator.free(cloned_content);

        const cloned_children = try allocator.dupe(usize, self.children);
        errdefer allocator.free(cloned_children);

        const cloned_conditions = try allocator.dupe(usize, self.conditions);
        errdefer allocator.free(cloned_conditions);

        return NodeData{
            .id = self.id,
            .content = cloned_content,
            .children = cloned_children,
            .conditions = cloned_conditions,
            .children_width = self.children_width,
            .depth = self.depth,
            .sibling_order = self.sibling_order,
            .actual_x = self.actual_x,
            .type = self.type,
        };
    }
    pub fn deinit(self: *NodeData, allocator: std.mem.Allocator) void {
        allocator.free(self.content);
        allocator.free(self.children);
        allocator.free(self.conditions);
    }
};

const SaveManager = @This();
loaded_save: ?*SaveData,
save_dir: [:0]const u8 = "saves/",
nb_of_saves: usize,
current_save: ?usize,

pub fn init(alloc: std.mem.Allocator) !*SaveManager {
    const save_manager = try alloc.create(SaveManager);

    var iter_dir = try std.fs.cwd().openDir("saves", .{ .iterate = true });
    defer {
        iter_dir.close();
    }
    var file_count: usize = 0;
    var iter = iter_dir.iterate();
    while (try iter.next()) |entry| {
        if (entry.kind == .file) file_count += 1;
    }

    save_manager.* = .{
        .loaded_save = null,
        .save_dir = "saves/",
        .nb_of_saves = file_count,
        .current_save = null,
    };

    return save_manager;
}

pub fn deinit(self: *SaveManager, allocator: std.mem.Allocator) void {
    if (self.loaded_save) |save| {
        save.deinit(allocator);
        allocator.destroy(save);
        self.loaded_save = null;
    }
}

fn collectNodes(node: *Node, save_data: *SaveData, allocator: std.mem.Allocator) !void {
    // Create and add current node data
    const node_data = try NodeData.fromNode(node, allocator);
    try save_data.addNode(node_data, allocator);

    // Recursively process all children
    for (node.children.items) |child| {
        try collectNodes(child, save_data, allocator);
    }
}

pub fn write_to_save(self: *SaveManager, node: *Node, allocator: std.mem.Allocator) !void {
    std.log.debug("Saving...", .{});

    //CONVERT NODES TO SAVEDATA

    var save_data = try SaveData.init(allocator);
    defer {
        save_data.deinit(allocator);
        allocator.destroy(save_data);
    }

    try collectNodes(node, save_data, allocator);

    //ACCESS FILE

    const file = try std.fs.cwd().createFile("saves/save.json", .{});
    defer file.close();

    var string = std.ArrayList(u8).init(allocator);
    defer string.deinit();

    //WRITE OUT SAVEDATA

    try std.json.stringify(save_data, .{ .whitespace = .indent_4 }, string.writer());
    try file.writeAll(string.items);

    _ = self;
    return;
}

pub fn read_from_save(self: *SaveManager, allocator: std.mem.Allocator) !?*SaveData {
    const file = try std.fs.cwd().openFile("saves/save.json", .{});
    defer file.close();

    const file_size = try file.getEndPos();
    const content = try file.readToEndAlloc(allocator, file_size);
    defer allocator.free(content);

    // Create a new SaveData instance
    self.deinit(allocator);

    // Parse the JSON
    var parsed = try std.json.parseFromSlice(SaveData, allocator, content, .{ .allocate = .alloc_always, .ignore_unknown_fields = true });
    defer parsed.deinit();

    self.loaded_save = try allocator.create(SaveData);
    errdefer allocator.destroy(self.loaded_save.?);
    // Clone the parsed data into our persistent SaveData
    if (self.loaded_save) |save| {
        save.* = try parsed.value.clone(allocator);
    }

    // Debug print all nodes with hierarchy
    //std.debug.print("\n=== Parsed Save Data ===\n", .{});
    //try printNodeHierarchy(self.loaded_save.nodes, 0, 0);

    return self.loaded_save;
}

fn printNodeHierarchy(nodes: []const NodeData, node_id: usize, depth: usize) !void {
    // Find the node with the given ID
    for (nodes) |node| {
        if (node.id == node_id) {
            // Print indentation based on depth
            for (0..depth) |_| {
                std.debug.print("  ", .{});
            }

            // Print node information
            std.debug.print("Node ID: {}\n", .{node.id});
            for (0..depth) |_| {
                std.debug.print("  ", .{});
            }
            std.debug.print("Content: {s}\n", .{node.content});
            for (0..depth) |_| {
                std.debug.print("  ", .{});
            }
            std.debug.print("Type: {}\n", .{node.type});
            for (0..depth) |_| {
                std.debug.print("  ", .{});
            }
            std.debug.print("Children: ", .{});
            for (node.children) |child_id| {
                std.debug.print("{} ", .{child_id});
            }
            std.debug.print("\n", .{});

            // Recursively print all children
            for (node.children) |child_id| {
                try printNodeHierarchy(nodes, child_id, depth + 1);
            }
            break;
        }
    }
}
