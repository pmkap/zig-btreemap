const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;

const getNodeType = @import("node.zig").Node;

pub fn BTreeMap(comptime K: type, comptime V: type) type {
    return struct {
        const Self = @This();

        root: ?*Node,
        allocator: Allocator,

        const B = 6;
        const Node = getNodeType(K, V, B);
        const KV = Node.KV;
        const SearchResult = Node.SearchResult;

        const StackItem = struct {
            node: *Node,
            index: usize,
        };

        pub fn init(allocator: Allocator) Self {
            return Self{
                .allocator = allocator,
                .root = null,
            };
        }

        pub fn deinit(self: Self) !void {
            var stack = std.ArrayList(*Node).init(self.allocator);
            defer stack.deinit();

            if (self.root) |root| {
                try stack.append(root);
            } else return;

            while (stack.popOrNull()) |node| {
                if (!node.isLeaf()) {
                    var i: usize = 0;
                    while (i < node.len + 1) : (i += 1) {
                        try stack.append(node.edges[i].?);
                    }
                }
                self.allocator.destroy(node);
            }
        }

        pub fn isEmpty(self: *const Self) bool {
            if (self.root == null) return true;
            return self.root.?.len == 0;
        }

        /// Get value from a certain key.
        pub fn get(self: Self, key: K) ?V {
            var current = self.root;
            while (current) |node| {
                const result = node.search(key);
                if (result.found) {
                    return node.values[result.index];
                } else {
                    current = node.edges[result.index];
                }
            }
            return null;
        }

        /// Inserts key-value pair into the map. Swaps the values if already present
        /// and returns the old.
        /// This function has two stages. In the first stage, the tree
        /// is traversed to find the path to the relevant leaf node.
        /// This path is saved in a stack, containing the nodes itself
        /// and the indices of the children where the path continues.
        /// In the second phase, we try to insert and, if the node is full,
        /// split the node and hand the result of the split down the stack.
        /// Repeat this until insertion is successful or the root itself is split.
        pub fn fetchPut(self: *Self, key: K, value: V) !?V {
            // TODO: return KV like in std.HashMap
            if (self.root == null) {
                self.root = try Node.createFromKV(self.allocator, key, value);
                return null;
            }

            var stack = std.ArrayList(StackItem).init(self.allocator);
            defer stack.deinit();

            // Traverse tree until we find the key or hit bottom.
            // If we we find the key, swap new with old value and return the old.
            // Build a stack to remember the path
            var current = self.root;
            var search_result: SearchResult = undefined;
            while (current) |node| {
                search_result = node.search(key);
                if (search_result.found) {
                    return node.swapValue(search_result.index, value);
                }
                // Not found, go deeper.
                current = node.edges[search_result.index];
                try stack.append(.{
                    .node = node,
                    .index = search_result.index,
                });
            }

            // Pop top of stack (bottom of tree/leaf node).
            var stack_next: ?StackItem = stack.pop();

            // Try to insert to leaf node.
            var split_result = try stack_next.?.node.insertOrSplit(
                self.allocator,
                stack_next.?.index,
                key,
                value,
                null,
            );

            // No split was necessary -> insertion was successful. We're Done.
            if (split_result == null) {
                return null;
            }

            // Split was necessary -> move down on stack.
            // The current node in stack was incorporated in the tree and the SplitResult.
            stack_next = stack.popOrNull();

            // Repeat the process of splitting and inserting until insertion is
            // successful or we hit the root node, in which case the root node is split.
            while (split_result) |split_result_unwrapped| {
                if (stack_next) |stack_next_unwrapped| {
                    // Try to insert the in current stack item.
                    split_result = try stack_next_unwrapped.node.insertOrSplit(
                        self.allocator,
                        stack_next_unwrapped.index,
                        split_result_unwrapped.key,
                        split_result_unwrapped.value,
                        split_result_unwrapped.edge,
                    );
                    stack_next = stack.popOrNull();
                } else {
                    // We reached the root.
                    var new_root = try Node.createFromKV(
                        self.allocator,
                        split_result_unwrapped.key,
                        split_result_unwrapped.value,
                    );
                    new_root.edges[0] = self.root;
                    new_root.edges[1] = split_result_unwrapped.edge;
                    self.root = new_root;
                    return null;
                }
            } else return null;
        }

        /// Removes and returns a key-value-pair. Returns null if not found.
        pub fn fetchRemove(self: *Self, key: K) !?KV {
            var stack = std.ArrayList(StackItem).init(self.allocator);
            defer stack.deinit();

            // Traverse tree until we find the key or hit bottom.
            // Build a stack to remember the path
            var current = self.root;
            var search_result: SearchResult = undefined;
            var found_key_ptr: ?*K = null;
            var found_value_ptr: ?*V = null;
            while (current) |node| {
                search_result = node.search(key);
                if (search_result.found) {
                    // Found! Remember pointers to key and value to swap later.
                    found_key_ptr = &node.keys[search_result.index];
                    found_value_ptr = &node.values[search_result.index];
                    // If not reached leaf, increment index in order to find the
                    // found key's inorder successor when we continue down the tree.
                    if (!node.isLeaf()) search_result.index += 1;
                }
                try stack.append(.{
                    .node = node,
                    .index = search_result.index,
                });
                current = node.edges[search_result.index];
                if (search_result.found) break;
            } else {
                // Key not found.
                return null;
            }

            // Continue building the stack to the inorder successor of the found key.
            while (current) |node| {
                try stack.append(.{
                    .node = node,
                    .index = 0,
                });
                current = node.edges[0];
            }
            // Reached leaf node. Stack is complete.

            // Leaf node is on top of stack now.
            var current_stack = stack.pop();

            // Swap the KV for deletion with its inorder successor.
            const out: KV = .{ .key = found_key_ptr.?.*, .value = found_value_ptr.?.* };
            found_key_ptr.?.* = current_stack.node.keys[current_stack.index];
            found_value_ptr.?.* = current_stack.node.values[current_stack.index];

            // Now ew can remove the key-value pair in the leaf. This can result in an underflow,
            // which is handled below.
            _ = current_stack.node.remove(current_stack.index);

            // If our leaf is also the root, it cannot underflow.
            if (current_stack.node == self.root) return out;

            // Fix underflow and move down the stack until underflow is fixed.
            while (current_stack.node.isLacking()) {
                // We have an underflow in the current stack position. This is fixed
                // from the parent's erspective, so move down the stack.
                current_stack = stack.pop();

                // Try to borrow, first from right, then from left.
                if (current_stack.node.borrowFromRight(current_stack.index)) return out;
                if (current_stack.node.borrowFromLeft(current_stack.index)) return out;

                // Borrow was not possible, merge nodes.
                if (current_stack.index == current_stack.node.len) {
                    // the underflowed edge is the most right. Merge with left.
                    current_stack.node.mergeEdges(self.allocator, current_stack.index - 1);
                } else {
                    // Merge with right.
                    current_stack.node.mergeEdges(self.allocator, current_stack.index);
                }

                if (current_stack.node == self.root) {
                    // We reached the root.
                    if (self.root.?.len == 0) {
                        // If root is empty, replace with merged node.
                        const new_root = current_stack.node.edges[0].?;
                        self.allocator.destroy(self.root.?);
                        self.root.? = new_root;
                    }
                    break;
                }
            }
            return out;
        }

        pub fn iteratorInit(self: *const Self) !Iterator {
            var new_stack = std.ArrayList(StackItem).init(self.allocator);
            if (self.root) |root| {
                try new_stack.append(.{
                    .node = root,
                    .index = 0,
                });
            }
            return Iterator{
                .stack = new_stack,
                .backwards = false,
            };
        }

        const Iterator = struct {
            stack: std.ArrayList(StackItem),
            backwards: bool,

            pub fn deinit(it: Iterator) void {
                it.stack.deinit();
            }

            pub fn next(it: *Iterator) !?KV {
                while (it.topStackItem()) |item| {
                    if (!item.node.isLeaf() and !it.backwards) {
                        // Child exists at index or going forward, go deeper.
                        const child = item.node.edges[item.index].?;
                        try it.stack.append(StackItem{
                            .node = child,
                            .index = 0,
                        });
                    } else {
                        // No Child or coming backwards.
                        if (item.index < item.node.len) {
                            // Node is not yet exhausted.
                            // Return KV from Node and increment the node's index.
                            const out = KV{
                                .key = item.node.keys[item.index],
                                .value = item.node.values[item.index],
                            };
                            item.index += 1;
                            it.backwards = false;
                            return out;
                        } else {
                            // Node is exhausted.
                            // Set `backwards` so that this node is not entered again
                            // in the next iteration.
                            _ = it.stack.popOrNull();
                            it.backwards = true;
                        }
                    }
                } else return null;
            }

            fn topStackItem(it: *Iterator) ?*StackItem {
                if (it.stack.items.len == 0) {
                    return null;
                } else {
                    return &it.stack.items[it.stack.items.len - 1];
                }
            }
        };

        /// Intended for testing and debugging. Traverses whole tree and
        /// asserts the validity of every node. Also if every leaf has the
        /// same height. -> BTree itself is valid.
        fn assertValidity(self: *const Self) !void {
            if (self.root == null) return;

            var depth: ?usize = null;
            var backwards = false;

            var stack = std.ArrayList(StackItem).init(self.allocator);
            defer stack.deinit();
            try stack.append(StackItem{
                .node = self.root.?,
                .index = 0,
            });
            self.root.?.assertValidityRoot();

            var item: *StackItem = undefined;
            while (stack.items.len >= 1) {
                item = &stack.items[stack.items.len - 1];
                if (!item.node.isLeaf() and !backwards) {
                    // Go deeper.
                    var child = item.node.edges[item.index].?;

                    child.assertValidity();

                    try stack.append(StackItem{
                        .node = child,
                        .index = 0,
                    });
                } else {
                    // Reached leaf or moving backwards

                    // Assert tree depth
                    if (item.node.isLeaf()) {
                        if (depth == null) {
                            depth = stack.items.len;
                        } else {
                            assert(stack.items.len == depth.?);
                        }
                    }

                    if (item.index < item.node.len) {
                        // Node is not yet exhausted.
                        item.index += 1;
                        backwards = false;
                    } else {
                        // Node is exhausted.
                        // Set `backwards` so that this node is not entered again
                        // in the next iteration.
                        _ = stack.popOrNull();
                        backwards = true;
                    }
                }
            }
        }
    };
}

const testing = std.testing;

test {
    const n = 10000;
    var keys = std.ArrayList(i16).init(testing.allocator);
    defer keys.deinit();

    var prng = std.rand.DefaultPrng.init(0);
    const random = prng.random();

    var i: i16 = 0;
    while (i < n) : (i += 1) {
        keys.append(random.int(i16)) catch unreachable;
    }

    var tree = BTreeMap(i32, i32).init(testing.allocator);
    defer tree.deinit() catch unreachable;

    for (keys.items) |j| {
        _ = try tree.fetchPut(j, j);
    }

    _ = try tree.fetchPut(11111, 99999);
    _ = try tree.fetchPut(22222, 88888);

    //var it = try tree.iteratorInit();
    //defer it.deinit();
    //while (it.next() catch unreachable) |item| std.debug.print("{any}\n", .{item});

    try testing.expect((try tree.fetchPut(11111, 0)).? == 99999);
    try testing.expectEqual(
        (try tree.fetchRemove(22222)).?,
        @TypeOf(tree).Node.KV{
            .key = 22222,
            .value = 88888,
        },
    );

    try tree.assertValidity();

    random.shuffle(i16, keys.items);
    for (keys.items) |j| {
        const out = try tree.fetchRemove(j);
        if (out) |u| {
            try testing.expect(u.key == j);
            try testing.expect(u.value == j);
        }
    }
    _ = try tree.fetchRemove(11111);

    try testing.expect(tree.isEmpty());
}

test "structs as keys" {
    const Car = struct {
        power: i32,
        pub fn lt(a: @This(), b: @This()) bool {
            return a.power < b.power;
        }
        pub fn eq(a: @This(), b: @This()) bool {
            return a.power == b.power;
        }
    };

    const n = 50;
    var cars = std.ArrayList(Car).init(testing.allocator);
    defer cars.deinit();

    var prng = std.rand.DefaultPrng.init(0);
    const random = prng.random();

    var i: u32 = 0;
    while (i < n) : (i += 1) {
        const power: i32 = @as(i32, random.int(u8)) + 100;
        cars.append(Car{ .power = power }) catch unreachable;
    }

    var tree = BTreeMap(Car, bool).init(testing.allocator);
    defer tree.deinit() catch unreachable;

    for (cars.items) |j| {
        _ = try tree.fetchPut(j, true);
    }

    for (cars.items) |j| {
        _ = try tree.fetchRemove(j);
    }
}
