const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;

pub fn Node(comptime K: type, comptime V: type, comptime B: u32) type {
    return struct {
        const Self = @This();

        keys: [2 * B - 1]K,
        values: [2 * B - 1]V,
        len: usize,
        edges: [2 * B]?*Self,

        // Return Type for Node's search method.
        pub const SearchResult = struct {
            found: bool,
            index: usize,
        };

        pub const KV = struct {
            key: K,
            value: V,
        };

        const KVE = struct {
            key: K,
            value: V,
            edge: ?*Self,
        };

        const Entry = struct {
            key_ptr: *K,
            value_ptr: *V,
        };

        pub fn createEmpty(allocator: Allocator) !*Self {
            var out = try allocator.create(Self);
            out.* = Self{
                .keys = [_]K{undefined} ** (2 * B - 1),
                .values = [_]V{undefined} ** (2 * B - 1),
                .len = 0,
                .edges = [_]?*Self{null} ** (2 * B),
            };
            return out;
        }

        pub fn createFromKV(allocator: Allocator, key: K, value: V) !*Self {
            var out = try Self.createEmpty(allocator);
            out.keys[0] = key;
            out.values[0] = value;
            out.len = 1;
            return out;
        }

        /// Searches the node for a key. Returns a struct with two fields:
        /// 1) .found: bool -> Wether the key was found or not.
        /// 2) .index: usize -> The index of the found key or, if no key was found,
        /// the index of the edge where the search path continues.
        pub fn search(self: Self, key: K) SearchResult {
            var i: usize = 0;
            while (i < self.len) : (i += 1) {
                if (key == self.keys[i]) {
                    return SearchResult{
                        .found = true,
                        .index = i,
                    };
                } else if (key < self.keys[i]) {
                    return .{
                        .found = false,
                        .index = i,
                    };
                }
            }
            return .{
                .found = false,
                .index = self.len,
            };
        }

        /// Insert KVE if node has room. Return null in this case.
        /// If node is full, split of the right part into a new node
        /// and return this new node together with the KVE.
        pub fn insertOrSplit(
            self: *Self,
            allocator: Allocator,
            index: usize,
            key: K,
            value: V,
            edge: ?*Self,
        ) !?KVE {
            if (self.isFull()) {
                // Node is full. Split Node.
                var split_result = try self.split(allocator);
                if (index < B) {
                    // Insert KVE in original node.
                    self.insert(index, key, value, edge);
                } else {
                    // Insert KVE in the split off node.
                    split_result.edge.?.insert(index - B, key, value, edge);
                }
                return split_result;
            } else {
                // No split necessary.
                self.insert(index, key, value, edge);
                return null;
            }
        }

        /// Swap value at index.
        pub fn swapValue(self: *Self, index: usize, value: V) V {
            const out = self.values[index];
            self.values[index] = value;
            return out;
        }

        /// Swap KV at index.
        pub fn swapKV(self: *Self, index: usize, key: K, value: V) KV {
            const out = KV{
                .key = self.keys[index],
                .value = self.values[index],
            };
            self.values[index] = value;
            self.keys[index] = key;
            return out;
        }

        /// Remove and return KVE at index.
        /// The removed edge is right of the KV.
        pub fn remove(self: *Self, index: usize) KVE {
            const out = KVE{
                .key = self.keys[index],
                .value = self.values[index],
                .edge = self.edges[index + 1],
            };

            std.mem.copy(
                K,
                self.keys[index..],
                self.keys[index + 1 .. self.len],
            );
            std.mem.copy(
                V,
                self.values[index..],
                self.values[index + 1 .. self.len],
            );

            self.keys[self.len - 1] = undefined;
            self.values[self.len - 1] = undefined;

            if (!self.isLeaf()) {
                std.mem.copy(
                    ?*Self,
                    self.edges[index + 1 ..],
                    self.edges[index + 2 .. self.len + 1],
                );
                self.edges[self.len] = null;
            }

            self.len -= 1;
            return out;
        }

        /// Remove and return most right KVE.
        fn removeFromEnd(self: *Self) KVE {
            return self.remove(self.len - 1);
        }

        /// Remove and return most left KV and Edge.
        /// Contrary to the methods above, this removes the edge left of the KV.
        fn removeFromBeginning(self: *Self) KVE {
            const out = KVE{
                .key = self.keys[0],
                .value = self.values[0],
                .edge = self.edges[0],
            };

            std.mem.copy(
                K,
                self.keys[0..],
                self.keys[1..self.len],
            );
            std.mem.copy(
                V,
                self.values[0..],
                self.values[1..self.len],
            );

            self.keys[self.len - 1] = undefined;
            self.values[self.len - 1] = undefined;

            if (!self.isLeaf()) {
                std.mem.copy(
                    ?*Self,
                    self.edges[0..],
                    self.edges[1 .. self.len + 1],
                );
                self.edges[self.len] = null;
            }
            self.len -= 1;
            return out;
        }

        // Shifts the arrays right after index and inserts new KVE.
        // The new edge is right of the new KV.
        // Does not check if insertion is at the correct position/node has space.
        fn insert(self: *Self, index: usize, key: K, value: V, edge: ?*Self) void {
            std.mem.copyBackwards(
                K,
                self.keys[index + 1 .. self.len + 1],
                self.keys[index..self.len],
            );
            self.keys[index] = key;

            std.mem.copyBackwards(
                V,
                self.values[index + 1 .. self.len + 1],
                self.values[index..self.len],
            );
            self.values[index] = value;

            if (!self.isLeaf()) {
                std.mem.copyBackwards(
                    ?*Self,
                    self.edges[index + 2 .. self.len + 2],
                    self.edges[index + 1 .. self.len + 1],
                );
                self.edges[index + 1] = edge;
            }

            self.len += 1;
        }

        /// Does not check if insertion is at the correct position/node has space.
        fn insertAtEnd(self: *Self, key: K, value: V, edge: ?*Self) void {
            self.keys[self.len] = key;
            self.values[self.len] = value;
            self.edges[self.len + 1] = edge;
            self.len += 1;
        }

        /// This is different from the other inserts methods because it inserts the edge
        /// left of the KV. I.e. it also puts the edge in the first position.
        /// Does not check if insertion is at the correct position/node has space.
        fn insertAtBeginning(self: *Self, key: K, value: V, edge: ?*Self) void {
            std.mem.copyBackwards(
                K,
                self.keys[1 .. self.len + 1],
                self.keys[0..self.len],
            );
            self.keys[0] = key;

            std.mem.copyBackwards(
                V,
                self.values[1 .. self.len + 1],
                self.values[0..self.len],
            );
            self.values[0] = value;

            if (!self.isLeaf()) {
                std.mem.copyBackwards(
                    ?*Self,
                    self.edges[1 .. self.len + 2],
                    self.edges[0 .. self.len + 1],
                );
                self.edges[0] = edge;
            }

            self.len += 1;
        }

        /// The borrowing methods happen from the perspective of the parent.
        /// This means, the parent distributes from one edge to another.
        /// The edge at `index` is underflowed and needs compensation.
        /// Try to borrow from the edge at one side of `index` and rotate.
        /// Returns true on success, else false.
        pub fn borrowFromRight(self: *Self, index: usize) bool {
            // No edge right of index.
            if (index == self.len) return false;

            var giver = self.edges[index + 1].?;

            if (giver.len > B - 1) {
                // Right edge can spare one.
                var taker = self.edges[index].?;

                const from_giver: KVE = giver.removeFromBeginning();
                taker.insertAtEnd(self.keys[index], self.values[index], from_giver.edge);
                _ = self.swapKV(index, from_giver.key, from_giver.value);
                return true;
            } else return false;
        }

        /// The borrowing methods happen from the perspective of the parent.
        /// This means, the parent distributes from one edge to another.
        /// The edge at `index` is underflowed and needs compensation.
        /// Try to borrow from the edge at one side of `index` and rotate.
        /// Returns true on success, else false.
        pub fn borrowFromLeft(self: *Self, index: usize) bool {
            // No edge left of index.
            if (index == 0) return false;

            var giver = self.edges[index - 1].?;

            if (giver.len > B - 1) {
                // Right edge can spare one.
                var taker = self.edges[index].?;

                const from_giver: KVE = giver.removeFromEnd();
                taker.insertAtBeginning(self.keys[index - 1], self.values[index - 1], from_giver.edge);
                _ = self.swapKV(index - 1, from_giver.key, from_giver.value);
                return true;
            } else return false;
        }

        /// Merging happend from the perspective of the parent.
        /// It merges two edges together and puts the middle KV of the parent in between.
        /// The right node is merged into the left and the right is destroyed afterwards.
        pub fn mergeEdges(self: *Self, allocator: Allocator, left_edge_index: usize) void {
            var left = self.edges[left_edge_index].?;
            const removed = self.remove(left_edge_index);

            left.insertAtEnd(removed.key, removed.value, null);

            std.mem.copyBackwards(
                K,
                left.keys[left.len..],
                removed.edge.?.keys[0..removed.edge.?.len],
            );
            std.mem.copyBackwards(
                V,
                left.values[left.len..],
                removed.edge.?.values[0..removed.edge.?.len],
            );
            std.mem.copyBackwards(
                ?*Self,
                left.edges[left.len..],
                removed.edge.?.edges[0 .. removed.edge.?.len + 1],
            );

            left.len += removed.edge.?.len;

            allocator.destroy(removed.edge.?);
        }

        /// Split operation for a full node.
        /// Returns a struct with three fields:
        /// 1) and 2) -> Key and value of the median.
        /// 3) -> The right part of the median as a new node (pointer).
        /// These parts are erased from the original node.
        fn split(self: *Self, allocator: Allocator) !KVE {
            const median: usize = B - 1;
            var new_key = self.keys[median];
            var new_value = self.values[median];

            var new_node = try Self.createFromSlices(
                allocator,
                self.keys[median + 1 .. self.len],
                self.values[median + 1 .. self.len],
                self.edges[median + 1 .. self.len + 1],
            );

            // shrink original node
            std.mem.set(K, self.keys[median..], undefined);
            std.mem.set(V, self.values[median..], undefined);
            std.mem.set(?*Self, self.edges[median + 1 ..], null);
            self.len = median;

            return KVE{
                .key = new_key,
                .value = new_value,
                .edge = new_node,
            };
        }

        fn createFromSlices(allocator: Allocator, keys: []K, values: []V, edges: []?*Self) !*Self {
            var out = try Self.createEmpty(allocator);
            std.mem.copyBackwards(K, out.keys[0..], keys);
            std.mem.copyBackwards(V, out.values[0..], values);
            std.mem.copyBackwards(?*Self, out.edges[0..], edges);
            out.len = keys.len;
            return out;
        }

        pub fn isLeaf(self: Self) bool {
            return self.edges[0] == null;
        }

        pub fn isFull(self: Self) bool {
            return self.len == 2 * B - 1;
        }

        pub fn isLacking(self: Self) bool {
            return self.len < B - 1;
        }

        /// This is intended for testing and debugging.
        fn assertValidityExceptLength(self: *const Self) void {
            // Keys increasing
            for (self.keys[0 .. self.len - 1]) |_, i| {
                assert(self.keys[i] < self.keys[i + 1]);
            }

            // Number of edges
            var count: u32 = 0;
            var encountered_null = false;
            for (self.edges) |edge| {
                if (edge) |_| {
                    assert(encountered_null == false);
                    count += 1;
                } else {
                    encountered_null = true;
                }
            }
            assert(count == self.len + 1 or count == 0);

            // If node is leaf we are done here.
            if (self.isLeaf()) return;

            // Edges left smaller and right larger
            for (self.keys[0..self.len]) |key, i| {
                const left_edge = self.edges[i].?;
                const imm_left_key = left_edge.keys[left_edge.len - 1];
                assert(key > imm_left_key);

                const right_edge = self.edges[i + 1].?;
                const imm_right_key = right_edge.keys[0];
                assert(key < imm_right_key);
            }
        }

        pub fn assertValidity(self: *const Self) void {
            // Length
            assert(self.len <= 2 * B - 1);
            assert(self.len >= B - 1);

            self.assertValidityExceptLength();
        }

        pub fn assertValidityRoot(self: *const Self) void {
            // Length
            assert(self.len <= 2 * B - 1);

            self.assertValidityExceptLength();
        }
    };
}
