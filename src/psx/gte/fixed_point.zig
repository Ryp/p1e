const std = @import("std");

// Fixed point type builder
// See https://en.wikipedia.org/wiki/Q_(number_format)
//
// This class is used to keep track of the fixed point location at compile time
pub fn Q(comptime integer_bits: comptime_int, comptime fraction_bits: comptime_int) type {
    const total_bits = 1 + integer_bits + fraction_bits;
    const backing_int = @Int(.signed, total_bits);

    return packed struct(backing_int) {
        pub const IntegerBits = integer_bits;
        pub const FractionBits = fraction_bits;
        pub const TotalBits = total_bits;
        pub const BackingInt = backing_int;
        pub const Self = @This();

        backing_value: backing_int,

        pub fn init(backing_value: backing_int) @This() {
            const T = @TypeOf(backing_value);
            if (T != comptime_int) {
                const info = @typeInfo(T);
                if (info != .int) @compileError(std.fmt.comptimePrint("{s}.init: expected an integer, got {s}", .{ @typeName(Self), @typeName(T) }));
                const needed = info.int.bits + @intFromBool(info.int.signedness == .unsigned);
                if (needed > @bitSizeOf(BackingInt))
                    @compileError(std.fmt.comptimePrint("{s}.init: {s} does not fit in {s}", .{ @typeName(Self), @typeName(T), @typeName(BackingInt) }));
            }
            return .{ .backing_value = backing_value };
        }

        pub fn lift(self: @This(), shift: comptime_int) Q(IntegerBits, FractionBits + shift) {
            const ResultQ = Q(IntegerBits, FractionBits + shift);

            return .init(@as(ResultQ.BackingInt, self.backing_value) << shift);
        }

        pub fn widen(self: @This(), target_type: anytype) target_type {
            if (FractionBits != target_type.FractionBits) {
                @compileError("widen must keep the same fraction bits");
            }
            if (IntegerBits >= target_type.IntegerBits) {
                @compileError("widen should actually widen");
            }

            return .init(self.backing_value);
        }

        pub fn truncate(self: @This(), target_type: anytype) target_type {
            if (target_type.FractionBits != FractionBits) {
                @compileError("Truncate must keep the same fraction bits");
            }

            return .init(@truncate(self.backing_value));
        }

        pub fn add(self: @This(), other: anytype) @This() {
            if (IntegerBits != @TypeOf(other).IntegerBits or FractionBits != @TypeOf(other).FractionBits) {
                @compileError(std.fmt.comptimePrint("{s}.add: {s} does not match", .{ @typeName(Self), @typeName(@TypeOf(other)) }));
            }

            return .init(self.backing_value + other.backing_value);
        }

        pub fn sub(self: @This(), other: anytype) @This() {
            if (IntegerBits != @TypeOf(other).IntegerBits or FractionBits != @TypeOf(other).FractionBits) {
                @compileError(std.fmt.comptimePrint("{s}.add: {s} does not match", .{ @typeName(Self), @typeName(@TypeOf(other)) }));
            }

            return .init(self.backing_value - other.backing_value);
        }

        pub fn mul(self: @This(), other: anytype) Q(IntegerBits + @TypeOf(other).IntegerBits + 1, FractionBits + @TypeOf(other).FractionBits) {
            const ResultQ = Q(IntegerBits + @TypeOf(other).IntegerBits + 1, FractionBits + @TypeOf(other).FractionBits);

            return .init(@as(ResultQ.BackingInt, self.backing_value) * @as(ResultQ.BackingInt, other.backing_value));
        }
    };
}


