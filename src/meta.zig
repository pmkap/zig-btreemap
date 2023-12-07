const std = @import("std");
const assert = std.debug.assert;
const expect = std.testing.expect;

/// Similiar to std.meta.eql but pointers are followed.
/// Also Unions and ErrorUnions are excluded.
pub fn eq(a: anytype, b: @TypeOf(a)) bool {
    const T = @TypeOf(a);

    switch (@typeInfo(T)) {
        .Int, .ComptimeInt, .Float, .ComptimeFloat => {
            return a == b;
        },
        .Struct => {
            if (!@hasDecl(T, "eq")) {
                @compileError("An 'eq' comparison method has to implemented for Type '" ++ @typeName(T) ++ "'");
            }
            return T.eq(a, b);
        },
        .Array => {
            for (a, 0..) |_, i|
                if (!eq(a[i], b[i])) return false;
            return true;
        },
        .Vector => |info| {
            var i: usize = 0;
            while (i < info.len) : (i += 1) {
                if (!eq(a[i], b[i])) return false;
            }
            return true;
        },
        .Pointer => |info| {
            switch (info.size) {
                .One => return eq(a.*, b.*),
                .Slice => {
                    if (a.len != b.len) return false;
                    for (a, 0..) |_, i|
                        if (!eq(a[i], b[i])) return false;
                    return true;
                },
                .Many => {
                    if (info.sentinel) {
                        if (std.mem.len(a) != std.mem.len(b)) return false;
                        var i: usize = 0;
                        while (i < std.mem.len(a)) : (i += 1)
                            if (!eq(a[i], b[i])) return false;
                        return true;
                    }
                    @compileError("Cannot compare many-item pointer to unknown number of items without sentinel value");
                },
                .C => @compileError("Cannot compare C pointers"),
            }
        },
        .Optional => {
            if (a == null and b == null) return true;
            if (a == null or b == null) return false;
            return eq(a.?, b.?);
        },
        else => {
            @compileError("Cannot compare type '" ++ @typeName(T) ++ "'");
        },
    }
}

pub fn lt(a: anytype, b: @TypeOf(a)) bool {
    const T = @TypeOf(a);

    switch (@typeInfo(T)) {
        .Int, .ComptimeInt, .Float, .ComptimeFloat => {
            return a < b;
        },
        .Struct => {
            if (!@hasDecl(T, "lt")) {
                @compileError("A 'lt' comparison method has to implemented for Type '" ++ @typeName(T) ++ "'");
            }
            return T.lt(a, b);
        },
        .Array => {
            for (a, 0..) |_, i| {
                if (lt(a[i], b[i])) {
                    return true;
                } else if (eq(a[i], b[i])) {
                    continue;
                } else {
                    return false;
                }
            }
            return false;
        },
        .Vector => |info| {
            var i: usize = 0;
            while (i < info.len) : (i += 1) {
                if (lt(a[i], b[i])) {
                    return true;
                } else if (eq(a[i], b[i])) {
                    continue;
                } else {
                    return false;
                }
            }
            return false;
        },
        .Pointer => |info| {
            switch (info.size) {
                .One => return lt(a.*, b.*),
                .Slice => {
                    const n = @min(a.len, b.len);
                    for (a[0..n], 0..) |_, i| {
                        if (lt(a[i], b[i])) {
                            return true;
                        } else if (eq(a[i], b[i])) {
                            continue;
                        } else {
                            return false;
                        }
                    }
                    return lt(a.len, b.len);
                },
                .Many => {
                    if (info.sentinel) {
                        const n = @min(std.mem.len(a), std.mem.len(b));
                        var i: usize = 0;
                        while (i < n) : (i += 1) {
                            if (lt(a[i], b[i])) {
                                return true;
                            } else if (eq(a[i], b[i])) {
                                continue;
                            } else {
                                return false;
                            }
                        }
                        return lt(std.mem.len(a), std.mem.len(b));
                    }
                    @compileError("Cannot compare many-item pointer to unknown number of items without sentinel value");
                },
                .C => @compileError("Cannot compare C pointers"),
            }
        },
        .Optional => {
            if (a == null or b == null) return false;
            return lt(a.?, b.?);
        },
        else => {
            @compileError("Cannot compare type '" ++ @typeName(T) ++ "'");
        },
    }
}

pub fn le(a: anytype, b: @TypeOf(a)) bool {
    return lt(a, b) or eq(a, b);
}

pub fn gt(a: anytype, b: @TypeOf(a)) bool {
    return !lt(a, b) and !eq(a, b);
}

pub fn ge(a: anytype, b: @TypeOf(a)) bool {
    return !lt(a, b);
}

test "numerals" {
    try expect(eq(1.0, 1.0));
    try expect(!eq(1.0, 1.1));

    try expect(lt(1.0, 2.0));
    try expect(!lt(1, 1));
    try expect(!lt(2, 1));
}

test "Arrays" {
    try expect(eq("abc", "abc"));
    try expect(!eq("abc", "abb"));

    try expect(lt("ab", "ba"));
    try expect(lt("aaa", "aab"));
    try expect(!lt("aaa", "aaa"));
    try expect(!lt("aab", "aaa"));
}

test "structs" {
    const Car = struct {
        power: i32,
        pub fn lt(a: @This(), b: @This()) bool {
            return a.power < b.power;
        }
        pub fn eq(a: @This(), b: @This()) bool {
            return a.power == b.power;
        }
    };

    const car1 = Car{ .power = 100 };
    const car2 = Car{ .power = 200 };

    try expect(eq(car1, car1));
    try expect(!eq(car1, car2));

    try expect(lt(car1, car2));
    try expect(!lt(car1, car1));
}

test "Slices" {
    const o: usize = 0;
    // assert(@TypeOf("abc"[o..]) == [:0]const u8);

    try expect(eq("abc"[o..], "abc"));
    try expect(!eq("abc"[o..], "abb"));

    try expect(lt(@as([:0]const u8, "aba"[o..]), @as([:0]const u8, "ba")));
    try expect(lt(@as([:0]const u8, "aaa"[o..]), @as([:0]const u8, "bb")));
    try expect(!lt(@as([:0]const u8, "aba"[o..]), @as([:0]const u8, "aa")));
    try expect(!lt("aaa"[o..], "aaa"));
    try expect(lt(@as([:0]const u8, "aaa"[o..]), @as([:0]const u8, "aaaa")));
    try expect(!lt(@as([:0]const u8, "aaa"[o..]), @as([:0]const u8, "aa")));
    try expect(lt(@as([:0]const u8, "aab"[o..]), @as([:0]const u8, "aaba")));
}

test "Optionals" {
    const x: ?i32 = 1;
    const y: ?i32 = 2;
    try expect(lt(x, y));
}

test "sentinel terminated pointers" {
    // TODO
}

test "Vectors" {
    // TODO
}
