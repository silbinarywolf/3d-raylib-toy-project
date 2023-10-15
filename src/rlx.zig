// rlx is raylib extensions
const std = @import("std");
const rl = @import("raylib");

// Moves the position forward
pub fn moveForward(camera: *rl.Camera, position: rl.Vector3, distance: f32, comptime moveInWorldPlane: bool) rl.Vector3 {
    var forward = getCameraForward(camera);

    if (moveInWorldPlane) {
        // Project vector onto world plane
        forward.y = 0;
        forward = vector3Normalize(forward);
    }

    // Scale by distance
    forward = vector3Scale(forward, distance);

    // Move position
    return vector3Add(position, forward);
}

// Moves the position in its current right direction
pub fn moveRight(camera: *rl.Camera, position: rl.Vector3, distance: f32, comptime moveInWorldPlane: bool) rl.Vector3 {
    var right = getCameraRight(camera);

    if (moveInWorldPlane) {
        // Project vector onto world plane
        right.y = 0;
        right = vector3Normalize(right);
    }

    // Scale by distance
    right = vector3Scale(right, distance);

    // Move position and target
    return vector3Add(position, right);
}

// Moves the position in its up direction
pub fn moveUp(camera: *rl.Camera, position: rl.Vector3, distance: f32) void {
    var up = getCameraUp(camera);

    // Scale by distance
    up = vector3Scale(up, distance);

    // Move position and target
    return vector3Add(position, up);
}

// Moves the camera in its up direction
pub fn cameraMoveUp(camera: *rl.Camera, distance: f32) void {
    var up = getCameraUp(camera);

    // Scale by distance
    up = vector3Scale(up, distance);

    // Move position and target
    camera.position = vector3Add(camera.position, up);
    camera.target = vector3Add(camera.target, up);
}

// Moves the camera in its forward direction
pub fn cameraMoveForward(camera: *rl.Camera, distance: f32, moveInWorldPlane: bool) void {
    var forward = getCameraForward(camera);

    if (moveInWorldPlane) {
        // Project vector onto world plane
        forward.y = 0;
        forward = vector3Normalize(forward);
    }

    // Scale by distance
    forward = vector3Scale(forward, distance);

    // Move position and target
    camera.position = vector3Add(camera.position, forward);
    camera.target = vector3Add(camera.target, forward);
}

// Moves the camera target in its current right direction
pub fn cameraMoveRight(camera: *rl.Camera, distance: f32, moveInWorldPlane: bool) void {
    var right = getCameraRight(camera);

    if (moveInWorldPlane) {
        // Project vector onto world plane
        right.y = 0;
        right = vector3Normalize(right);
    }

    // Scale by distance
    right = vector3Scale(right, distance);

    // Move position and target
    camera.position = vector3Add(camera.position, right);
    camera.target = vector3Add(camera.target, right);
}

// Returns the cameras up vector (normalized)
// Note: The up vector might not be perpendicular to the forward vector
pub fn getCameraUp(camera: *rl.Camera) rl.Vector3 {
    return vector3Normalize(camera.up);
}

// Returns the cameras right vector (normalized)
pub fn getCameraRight(camera: *rl.Camera) rl.Vector3 {
    var forward = getCameraForward(camera);
    var up = getCameraUp(camera);

    return vector3CrossProduct(forward, up);
}

// Moves the camera in its forward direction
pub fn getCameraForward(camera: *rl.Camera) rl.Vector3 {
    return vector3Normalize(vector3Subtract(camera.target, camera.position));
}

// Add two vectors
pub fn vector3Add(v1: rl.Vector3, v2: rl.Vector3) rl.Vector3 {
    var result: rl.Vector3 = .{ .x = v1.x + v2.x, .y = v1.y + v2.y, .z = v1.z + v2.z };
    return result;
}

// Subtract two vectors
pub fn vector3Subtract(v1: rl.Vector3, v2: rl.Vector3) rl.Vector3 {
    var result: rl.Vector3 = .{ .x = v1.x - v2.x, .y = v1.y - v2.y, .z = v1.z - v2.z };
    return result;
}

// Multiply vector by scalar
pub fn vector3Scale(v: rl.Vector3, scalar: f32) rl.Vector3 {
    var result: rl.Vector3 = .{ .x = v.x * scalar, .y = v.y * scalar, .z = v.z * scalar };
    return result;
}

// Normalize provided vector
pub fn vector3Normalize(v: rl.Vector3) rl.Vector3 {
    var result = v;

    var length: f32 = std.math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z);
    if (length != 0.0) {
        var ilength: f32 = 1.0 / length;

        result.x *= ilength;
        result.y *= ilength;
        result.z *= ilength;
    }

    return result;
}

// Calculate two vectors cross product
pub fn vector3CrossProduct(v1: rl.Vector3, v2: rl.Vector3) rl.Vector3 {
    var result: rl.Vector3 = .{ .x = v1.y * v2.z - v1.z * v2.y, .y = v1.z * v2.x - v1.x * v2.z, .z = v1.x * v2.y - v1.y * v2.x };
    return result;
}

// drawTextf will draw formatted text with raylib
pub fn drawTextf(comptime fmt: []const u8, args: anytype, posX: i32, posY: i32, fontSize: i32, color: rl.Color) !void {
    const MAX_TEXT_SIZE = 2048;
    var bounded_array = std.BoundedArray(u8, MAX_TEXT_SIZE){};
    var writer = bounded_array.writer();
    try std.fmt.format(writer, fmt, args);
    bounded_array.appendAssumeCapacity(0);
    const slice = bounded_array.slice();
    rl.drawText(slice[0 .. slice.len - 1 :0], posX, posY, fontSize, color);
}
