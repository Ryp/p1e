const std = @import("std");

const PSXState = @import("../state.zig").PSXState;
const config = @import("../config.zig");

const Id = packed union {
    raw: u16,
    typed: packed struct(u16) {
        lo: u8,
        hi: u8,
    },
};

const DigitalId = 0x5a41;

const DigitalSwitches = packed struct(u16) {
    lo: packed struct(u8) {
        select: ButtonState = .Released,
        unused_b1_2: u2 = 0b11,
        start: ButtonState = .Released,
        up: ButtonState = .Released,
        right: ButtonState = .Released,
        down: ButtonState = .Released,
        left: ButtonState = .Released,
    } = .{},
    hi: packed struct(u8) {
        l2: ButtonState = .Released,
        r2: ButtonState = .Released,
        l1: ButtonState = .Released,
        r1: ButtonState = .Released,
        triangle: ButtonState = .Released,
        circle: ButtonState = .Released,
        cross: ButtonState = .Released,
        square: ButtonState = .Released,
    } = .{},

    const ButtonState = enum(u1) {
        Pressed = 0,
        Released = 1,
    };
};

pub const State = struct {
    id: Id = .{ .raw = DigitalId },
    switches: DigitalSwitches = .{},

    graph: StateEnum = .Idle,

    const StateEnum = enum {
        Idle,
        SendingIdLo,
        SendingIdHi,
        SendingSwitchesLo,
        SendingSwitchesHi,
    };

    pub fn send_byte(self: *@This(), msg: u8) u8 {
        const response, const next_state = self.get_next_byte_and_state(msg);

        self.graph = next_state;

        return response;
    }

    pub fn has_more_to_send(self: *@This()) bool {
        return self.graph != .Idle;
    }

    fn get_next_byte_and_state(self: *@This(), msg: u8) struct { u8, StateEnum } {
        switch (self.graph) {
            .Idle => {
                std.debug.assert(msg == 0x01);
                return .{ 0xff, .SendingIdLo };
            },
            .SendingIdLo => {
                if (msg == 0x42) {
                    return .{ self.id.typed.lo, .SendingIdHi };
                } else {
                    return .{ 0xff, .Idle };
                }
            },
            .SendingIdHi => {
                std.debug.assert(msg == 0x00); // TAP
                return .{ self.id.typed.hi, .SendingSwitchesLo };
            },
            .SendingSwitchesLo => {
                if (msg == 0x00) { // MOT
                    return .{ @bitCast(self.switches.lo), .SendingSwitchesHi };
                } else {
                    return .{ 0xff, .Idle };
                }
            },
            .SendingSwitchesHi => {
                if (msg == 0x00) { // MOT
                    return .{ @bitCast(self.switches.hi), .Idle };
                } else {
                    return .{ 0xff, .Idle };
                }
            },
        }

        @panic("Invalid!");
    }
};
