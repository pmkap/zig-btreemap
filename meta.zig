const std = @import("std");
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
            for (a) |_, i|
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
                    for (a) |_, i|
                        if (!eq(a[i], b[i])) return false;
                    return true;
                },
                .Many => @compileError("Cannot compare many-item pointer to unknown number of items"),
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
            for (a[0 .. a.len - 1]) |_, i|
                if (!lt(a[i], b[i]) and !eq(a[i], b[i])) return false;
            return a[a.len - 1] < b[a.len - 1];
        },
        .Vector => |info| {
            var i: usize = 0;
            while (i < info.len - 1) : (i += 1)
                if (!lt(a[i], b[i]) and !eq(a[i], b[i])) return false;
            return a[info.len - 1] < b[info.len - 1];
        },
        .Pointer => |info| {
            switch (info.size) {
                .One => return lt(a.*, b.*),
                .Slice => {
                    const n = std.math.min(a.len, b.len);
                    for (a[0..n]) |_, i|
                        if (!lt(a[i], b[i]) and !eq(a[i], b[i])) return false;
                    return lt(a.len, b.len);
                },
                .Many => @compileError("Cannot compare many-item pointer to unknown number of items"),
                // TODO: Maybe compare sentinel-terminated pointers.
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
    try expect(lt(1.0, 2.0));
    try expect(!lt(2, 1));
}

test "structs" {
    const Car = struct {
        power: i32,
        pub fn lt(a: @This(), b: @This()) bool {
            return a.power < b.power;
        }
    };

    var car1 = Car{ .power = 100 };
    var car2 = Car{ .power = 200 };

    try expect(lt(car1, car2));
    try expect(!lt(car2, car1));
}

test "Arrays" {
    try expect(eq([_]u8{ 1, 2, 3 }, [_]u8{ 1, 2, 3 }));
    try expect(!eq([_]u8{ 1, 2, 3 }, [_]u8{ 1, 2, 4 }));

    try expect(lt([_]u8{ 1, 2, 3 }, [_]u8{ 1, 2, 4 }));
    try expect(!lt([_]u8{ 1, 2, 3 }, [_]u8{ 1, 2, 3 }));
    try expect(!lt([_]u8{ 1, 2, 3 }, [_]u8{ 1, 2, 2 }));

    try expect(le([_]u8{ 1, 2, 3 }, [_]u8{ 1, 2, 4 }));
    try expect(le([_]u8{ 1, 2, 3 }, [_]u8{ 1, 2, 3 }));
    try expect(!le([_]u8{ 1, 2, 3 }, [_]u8{ 1, 2, 2 }));

    try expect(gt([_]u8{ 1, 2, 5 }, [_]u8{ 1, 2, 4 }));
    try expect(!gt([_]u8{ 1, 2, 3 }, [_]u8{ 1, 2, 3 }));
    try expect(!gt([_]u8{ 1, 2, 3 }, [_]u8{ 1, 2, 4 }));

    try expect(ge([_]u8{ 1, 2, 3 }, [_]u8{ 1, 2, 3 }));
    try expect(ge([_]u8{ 1, 2, 4 }, [_]u8{ 1, 2, 3 }));
    try expect(!ge([_]u8{ 1, 2, 3 }, [_]u8{ 1, 2, 4 }));
}

test "Slices" {
    var a = [_]u8{ 1, 2, 3, 1, 2, 3, 4, 7, 8, 9 };
    var zero: usize = 0;
    //var one: usize = 1;
    var two: usize = 2;
    var three: usize = 3;
    var five: usize = 5;
    try expect(lt(a[zero..3], a[zero..4]));
    try expect(eq(a[zero..3], a[three..6]));
    try expect(!eq(a[zero..3], a[three..7]));
    try expect(gt(a[two..3], a[zero..]));
    try expect(ge(a[five..], a[two..]));
    try expect(!le(a[two..], a[zero..]));
}

test "Optionals" {
    // TODO
}

test "Vectors" {
    // TODO
}
