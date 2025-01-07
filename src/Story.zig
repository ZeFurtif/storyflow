const std = @import("std");

const raylib = @import("raylib");
const raygui = @import("raygui");

const App = @import("App.zig");
const Node = @import("Node.zig");
const SaveManager = @import("SaveManager.zig");

const Story = @This(); // MY TREE
next_available_id: usize,
reuse_ids: std.ArrayList(usize),
root: *Node,
current_node_selected: *Node,
sibling_visited: usize,
saved: bool,

pub fn init(alloc: std.mem.Allocator) !*Story {
    const story = try alloc.create(Story);

    const _reuse_ids = std.ArrayList(usize).init(alloc);

    story.* = .{
        .next_available_id = 0,
        .reuse_ids = _reuse_ids,
        .root = undefined,
        .current_node_selected = undefined,
        .sibling_visited = 0,
        .saved = false,
    };

    return story;
}

pub fn deinit(self: *Story, alloc: std.mem.Allocator) void {
    //std.log.debug("next available id : {any}", .{self.next_available_id});
    if (self.next_available_id + self.reuse_ids.items.len > 0) {
        self.root.deinit(alloc);
        alloc.destroy(self.root);
        //alloc.destroy(self.current_node_selected);
    }
    self.reuse_ids.deinit();
}

pub fn has_current_node(self: *Story) bool {
    return self.next_available_id + self.reuse_ids.items.len != 0;
}

pub fn new_id(self: *Story) usize {
    if (self.reuse_ids.items.len == 0) {
        const _id = self.next_available_id;
        self.next_available_id += 1;
        return _id;
    } else {
        const _id = self.reuse_ids.orderedRemove(0);
        return _id;
    }
}

pub fn reconstructTree(self: *Story, save_data: SaveManager.SaveData, allocator: std.mem.Allocator) !void {
    // First clear existing tree if any
    if (self.has_current_node()) {
        self.clear(allocator);
    }

    // Create a hashmap to store node references by ID
    var node_map = std.AutoHashMap(usize, *Node).init(allocator);
    defer node_map.deinit();

    // First pass: Create all nodes without connections
    for (save_data.nodes) |node_data| {
        var _node = try Node.init(allocator, node_data.id);

        // Copy data from NodeData to Node
        try _node.content.appendSlice(node_data.content);
        _node.children_width = node_data.children_width;
        _node.depth = node_data.depth;
        _node.sibling_order = node_data.sibling_order;
        _node.actual_x = node_data.actual_x;
        _node.type = node_data.type;

        try node_map.put(node_data.id, _node);

        // Update Story's next_available_id if necessary
        if (node_data.id >= self.next_available_id) {
            self.next_available_id = node_data.id + 1;
        }
    }

    // Second pass: Connect nodes
    for (save_data.nodes) |node_data| {
        const current_node = node_map.get(node_data.id) orelse return error.NodeNotFound;

        // Connect children
        for (node_data.children) |child_id| {
            const child_node = node_map.get(child_id) orelse return error.NodeNotFound;
            try current_node.children.append(child_node);
            child_node.parent = current_node;
        }

        // Connect conditions (assuming conditions are also node IDs)
        for (node_data.conditions) |condition_id| {
            const condition_node = node_map.get(condition_id) orelse return error.NodeNotFound;
            try current_node.conditions.append(condition_node);
        }
    }

    // Find and set the root node (node with no parent or lowest depth)
    var root_node: ?*Node = null;
    var root_depth: usize = std.math.maxInt(usize);

    var node_iterator = node_map.valueIterator();
    while (node_iterator.next()) |node_ptr| {
        const node = node_ptr.*; // Dereference the pointer to get the Node
        if (node.depth < root_depth) {
            root_depth = node.depth;
            root_node = node_ptr.*;
        }
    }

    if (root_node) |root| {
        self.root = root;
        self.current_node_selected = root;
        self.sibling_visited = 0;
    } else {
        return error.NoRootNode;
    }

    // Recompute tree properties
    self.compute_tree();
}

pub fn clear(self: *Story, alloc: std.mem.Allocator) void {
    if (self.root != undefined) {
        self.root.*.free_recursive(alloc);
    }

    // Free reuse_ids array
    self.reuse_ids.deinit();

    // Reset the story state
    self.next_available_id = 0;
    self.root = undefined;
    self.current_node_selected = undefined;
    self.sibling_visited = 0;
    self.saved = false;
}

pub fn new_node(self: *Story, allocator: std.mem.Allocator) void {
    if (Node.init(allocator, self.new_id())) |node| {
        if (self.next_available_id + self.reuse_ids.items.len > 1) {
            node.parent = self.current_node_selected;
            self.current_node_selected.add_child(node);
            self.current_node_selected = node;
            self.sibling_visited = node.sibling_order;
        } else {
            self.root = node;
            self.current_node_selected = node;
        }
        //std.log.debug("Node : {} {} {}", .{ node.id, node.sibling_order, node.depth });
    } else |e| {
        std.log.debug("{any}", .{e});
    }
}

pub fn delete_node(self: *Story, alloc: std.mem.Allocator) !void {
    if (self.has_current_node() and self.current_node_selected != self.root) {
        const node = self.current_node_selected;
        const children = node.children;
        self.current_node_selected = self.current_node_selected.parent;

        for (children.items) |child| {
            child.parent = self.current_node_selected;
            try self.current_node_selected.children.append(child);
        }

        try self.reuse_ids.append(node.id);
        self.current_node_selected.deinit_child(node.sibling_order, alloc);

        self.current_node_selected.compute_children_order();
        self.current_node_selected.compute_children_depth(self.current_node_selected.depth);

        self.compute_tree();
    }
}

pub fn insert_parent(self: *Story, alloc: std.mem.Allocator) !void {
    if (self.has_current_node() and self.current_node_selected != self.root) {
        if (Node.init(alloc, self.new_id())) |node| {
            node.parent = self.current_node_selected.parent;
            try self.current_node_selected.parent.children.append(node);
            _ = self.current_node_selected.parent.children.orderedRemove(self.current_node_selected.sibling_order);
            try node.children.append(self.current_node_selected);
            self.current_node_selected.parent = node;
        } else |e| {
            std.log.debug("{any}", .{e});
        }
    }
    self.compute_tree();
}

pub fn insert_child(self: *Story, alloc: std.mem.Allocator) !void {
    if (self.has_current_node() and self.current_node_selected != self.root) {
        if (Node.init(alloc, self.new_id())) |node| {
            node.parent = self.current_node_selected;
            for (self.current_node_selected.children.items) |child| {
                try node.children.append(child);
                child.parent = node;
            }
            for (self.current_node_selected.children.items) |child| {
                _ = child;
                _ = self.current_node_selected.children.pop();
            }
            try self.current_node_selected.children.append(node);
        } else |e| {
            std.log.debug("{any}", .{e});
        }
    }
    self.compute_tree();
}

pub fn compute_tree(self: *Story) void {
    self.root.compute_children_order();
    self.root.compute_children_depth(0);
}

pub fn move_up(self: *Story) void { // TODO : MOVE ACROSS TREE
    if (self.current_node_selected != self.root) {
        self.current_node_selected = self.current_node_selected.parent;
    }
    self.sibling_visited = self.current_node_selected.sibling_order;
}

pub fn move_down(self: *Story) void {
    if (self.current_node_selected.children.items.len != 0) {
        self.current_node_selected = self.current_node_selected.children.items[0];
    }
    self.sibling_visited = self.current_node_selected.sibling_order;
}

pub fn move_prev(self: *Story) void {
    if (self.current_node_selected != self.root) {
        if (self.current_node_selected.parent.children.items.len > 0 and self.sibling_visited != 0) {
            self.sibling_visited -= 1;
            self.current_node_selected = self.current_node_selected.parent.children.items[self.sibling_visited];
        }
    }
}

pub fn move_next(self: *Story) void {
    if (self.current_node_selected != self.root) {
        if (self.sibling_visited < self.current_node_selected.parent.children.items.len - 1) {
            self.sibling_visited += 1;
            self.current_node_selected = self.current_node_selected.parent.children.items[self.sibling_visited];
        }
    }
}

pub fn rearange_up(self: *Story) !void {
    if (self.has_current_node()) {
        if (self.current_node_selected != self.root) {
            if (self.current_node_selected.parent.children.items.len > 1) {
                if (self.current_node_selected.sibling_order != 0) {
                    const to_switch = self.current_node_selected.parent.children.orderedRemove(self.current_node_selected.sibling_order - 1);
                    try self.current_node_selected.parent.children.insert(self.current_node_selected.sibling_order, to_switch);
                    self.sibling_visited = self.current_node_selected.sibling_order - 1;
                    self.compute_tree();
                }
            }
        }
    }
}

pub fn rearange_down(self: *Story) !void {
    if (self.has_current_node()) {
        if (self.current_node_selected != self.root) {
            if (self.current_node_selected.parent.children.items.len > 1) {
                if (self.current_node_selected.sibling_order != self.current_node_selected.parent.children.items.len - 1) {
                    const to_switch = self.current_node_selected.parent.children.orderedRemove(self.current_node_selected.sibling_order + 1);
                    try self.current_node_selected.parent.children.insert(self.current_node_selected.sibling_order, to_switch);
                    self.sibling_visited = self.current_node_selected.sibling_order + 1;
                    self.compute_tree();
                }
            }
        }
    }
}

pub fn evaluate_tree_size(self: *Story) void {
    _ = self.root.evaluate_offset(0);
}

pub fn render(self: *Story, settings: App.AppSettings) void {
    //std.log.debug("TREE : ", .{});
    if (self.next_available_id + self.reuse_ids.items.len > 0) {
        self.evaluate_tree_size();
        self.root.render(settings);
    }
}
