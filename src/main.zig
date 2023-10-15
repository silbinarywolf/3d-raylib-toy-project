// Learning notes:
// - https://www.raylib.com/examples/core/loader.html?name=core_3d_camera_first_person
//      - https://github.com/raysan5/raylib/blob/master/examples/core/core_3d_camera_first_person.c
// - https://www.raylib.com/examples/models/loader.html?name=models_mesh_picking
// - The unit of space/length/width/height/etc is in metres. ie. x = 1, 1 = 1 metre, this is the default in Blender too

const std = @import("std");
const rl = @import("raylib");
const rlx = @import("rlx.zig");
const wavefront = @import("wavefront.zig");

// targetTickRate is what all the physics/movement speeds, etc are tied to.
// Use this so that when can loop the simulation logic 2x if the FPS is half or 4x if it's a quarter.
//
// Not using deltatime or variable updating so the sim is simpler to implement and deterministic
const targetTickRate: i32 = 120;

const Image = enum(u8) {
    Grass,
    Sky,
};

const Settings = struct {
    isMusicEnabled: bool = false,
};

const Player = struct {
    const gravity: f32 = 0.0035;
    const jump_power: f32 = -0.12;
    const move_speed: f32 = 0.05;
    const size: f32 = 0.5;

    position: rl.Vector3 = .{
        .x = 0,
        .y = 0,
        .z = 0,
    },
    vspeed: f32 = 0,
    jumps_since_last_touched_ground: i8 = 0,
    has_beaten_level: bool = false,
};

const Cube = struct {
    const Self = @This();

    x: f32,
    y: f32,
    z: f32,
    width: f32,
    height: f32,
    length: f32,
    color: rl.Color = rl.Color.blue,

    pub fn boundingBox(self: *Self) rl.BoundingBox {
        var min = rl.Vector3.init(self.x - (self.width / 2), self.y - (self.height / 2), self.z - (self.length / 2));
        var max = min;
        max.x += self.width;
        max.y += self.height;
        max.z += self.length;
        return rl.BoundingBox{
            .min = min,
            .max = max,
        };
    }
};

const Collectable = struct {
    const Self = @This();
    const _size: f32 = 0.75;
    const width: f32 = _size;
    const height: f32 = _size;
    const length: f32 = _size;

    x: f32,
    y: f32,
    z: f32,
    rotate: f32 = 0,
    image: Image = Image.Grass,

    pub fn boundingBox(self: *Self) rl.BoundingBox {
        var min = rl.Vector3.init(self.x - (width / 2), self.y - (height / 2), self.z - (length / 2));
        var max = min;
        max.x += width;
        max.y += height;
        max.z += length;
        return rl.BoundingBox{
            .min = min,
            .max = max,
        };
    }
};

var camera = rl.Camera{
    .position = rl.Vector3.init(0.2, 0.4, 0.2),
    .target = rl.Vector3.init(0.185, 0.4, 0.0),
    .up = rl.Vector3.init(0.0, 1.0, 0.0),
    .fovy = 45.0,
    .projection = rl.CameraProjection.camera_perspective,
};

const ExitDoor = struct {
    const Self = @This();

    const width: f32 = 1.75;
    const height: f32 = 3.0;
    const length: f32 = 0.5;

    x: f32 = 0,
    y: f32 = 0,
    z: f32 = 0,

    pub fn boundingBox(self: *Self) rl.BoundingBox {
        var min = rl.Vector3.init(self.x - (width / 2), self.y - (height / 2), self.z - (length / 2));
        var max = min;
        max.x += width;
        max.y += height;
        max.z += length;
        return rl.BoundingBox{
            .min = min,
            .max = max,
        };
    }

    // note(jae): 2023-10-14
    // this is ineffecient but easy to code so it stays for now.
    // l-o-l
    fn getCubes(self: *Self) std.BoundedArray(Cube, 4) {
        var cubes: std.BoundedArray(Cube, 4) = .{};

        // generate walls around door
        const side_width: f32 = 0.25;
        {
            const cube = Cube{
                .x = self.x - (ExitDoor.width / 2) - (side_width / 2),
                .y = self.y,
                .z = self.z,
                .width = side_width,
                .height = ExitDoor.height,
                .length = ExitDoor.length,
                .color = rl.Color.red,
            };
            cubes.appendAssumeCapacity(cube);
        }
        {
            const cube = Cube{
                .x = self.x + (ExitDoor.width / 2) + (side_width / 2),
                .y = self.y,
                .z = self.z,
                .width = side_width,
                .height = ExitDoor.height,
                .length = ExitDoor.length,
                .color = rl.Color.red,
            };
            cubes.appendAssumeCapacity(cube);
        }
        {
            const top_height = side_width;
            const cube = Cube{
                .x = self.x,
                .y = self.y + (ExitDoor.height / 2) + (top_height / 2),
                .z = self.z,
                .width = ExitDoor.height,
                .height = top_height,
                .length = ExitDoor.length,
                .color = rl.Color.red,
            };
            cubes.appendAssumeCapacity(cube);
        }
        return cubes;
    }
};

const Level = struct {
    player_start_position: rl.Vector3 = rl.Vector3.init(0, 0, 0),
    player_has_start_position: bool = false,

    // exit door
    exit_door: ExitDoor = .{
        // default to being far away if not set
        .x = -9999,
        .y = -9999,
        .z = -9999,
    },

    // level geometry
    cubes: std.BoundedArray(Cube, 128) = .{},

    // stuff
    collectables: std.BoundedArray(Collectable, 128) = .{},
};

var settings: Settings = .{};

// currentLevel is the current state of the level
var currentLevel: Level = .{};

// loadedLevel is the loaded level data that hasn't been manipulated
var loadedLevel: Level = .{};

var player: Player = .{};

var gpa = std.heap.GeneralPurposeAllocator(.{
    .enable_memory_limit = true,
    // note(jae): 2023-08-20
    // Turning this on doesn't free memory so we can catch segfaults
    //.never_unmap = true,
}){
    // limit to 128mb of RAM
    .requested_memory_limit = 128 * 1024 * 1024,
};

fn hasCollisionAtPosition(position: rl.Vector3) bool {
    // Check collision
    for (currentLevel.cubes.slice()) |*cube| {
        if (rl.checkCollisionBoxSphere(cube.boundingBox(), position, @TypeOf(player).size)) {
            return true;
        }
    }
    if (currentLevel.collectables.len == 0) {
        var door_cubes = currentLevel.exit_door.getCubes();
        for (door_cubes.slice()) |*cube| {
            if (rl.checkCollisionBoxSphere(cube.boundingBox(), position, @TypeOf(player).size)) {
                return true;
            }
        }
    }
    return false;
}

var targetFps: i32 = 0;

// setTargetFPS exists as rl.setTargetFPS doesn't provide an API for getting current target FPS
fn setTargetFPS(fps: i32) void {
    rl.setTargetFPS(fps);
    targetFps = fps;
}

pub fn resetLevel() void {
    // reset level
    currentLevel = loadedLevel;

    // reset all fields to defaults
    player = .{};

    // set to start position
    player.position = currentLevel.player_start_position;

    // Push out of ground if colliding
    while (hasCollisionAtPosition(player.position)) {
        player.position.y += 0.001;
    }
}

pub fn main() anyerror!void {
    // Initialization
    //--------------------------------------------------------------------------------------
    const screenWidth: f32 = 1280;
    const screenHeight: f32 = 720;

    // Setup custom allocator
    defer {
        std.debug.print("deinit allocator\n--------------\n", .{});
        _ = gpa.deinit();
    }
    var allocator = gpa.allocator();
    _ = allocator;

    // add anti-aliasing
    rl.setConfigFlags(rl.ConfigFlags.flag_msaa_4x_hint);

    rl.initWindow(screenWidth, screenHeight, "The Game");
    defer rl.closeWindow(); // Close window and OpenGL context

    rl.initAudioDevice();
    defer rl.closeAudioDevice();

    // load level
    {
        var level: Level = .{};

        const level_data = @embedFile("resources/levels/level_one.obj");
        var wfparser = wavefront.Parser.init(level_data);
        while (try wfparser.next()) |obj| {
            if (std.mem.startsWith(u8, obj.object_name, "cube") or
                std.mem.startsWith(u8, obj.object_name, "Cube"))
            {
                // note(jae): 2023-10-08
                // Naively assume everything is a axis-aligned(?) cube and
                // get dimensions
                const bounds = obj.boundingBox();
                const min = bounds.min;
                const max = bounds.max;
                var width = @abs(min.x - max.x);
                var height = @abs(min.y - max.y);
                var length = @abs(min.z - max.z);
                var cube = Cube{
                    .x = min.x + (width / 2),
                    .y = min.y + (height / 2),
                    .z = min.z + (length / 2),
                    .width = width,
                    .height = height,
                    .length = length,
                };
                try level.cubes.append(cube);
            } else if (std.mem.startsWith(u8, obj.object_name, "collect") or
                std.mem.startsWith(u8, obj.object_name, "Collect"))
            {
                var image = Image.Sky;
                if (std.mem.endsWith(u8, obj.object_name, "Grass") or
                    std.mem.endsWith(u8, obj.object_name, "grass"))
                {
                    image = Image.Grass;
                }
                if (std.mem.endsWith(u8, obj.object_name, "Sky") or
                    std.mem.endsWith(u8, obj.object_name, "sky") or
                    std.mem.endsWith(u8, obj.object_name, "Skies") or
                    std.mem.endsWith(u8, obj.object_name, "skies"))
                {
                    image = Image.Sky;
                }
                // Collectibles ignore width/height/length and just use the predefined one
                const vec = obj.getCenter();
                try level.collectables.append(.{
                    .x = vec.x,
                    .y = vec.y,
                    .z = vec.z,
                    .image = image,
                });
            } else if (std.mem.startsWith(u8, obj.object_name, "player") or
                std.mem.startsWith(u8, obj.object_name, "Player"))
            {
                // Player ignore width/height/length and just use the predefined one
                const vec = obj.getCenter();
                level.player_start_position = .{
                    .x = vec.x,
                    .y = vec.y,
                    .z = vec.z,
                };
                level.player_has_start_position = true;
            } else if (std.mem.startsWith(u8, obj.object_name, "exitdoor") or
                std.mem.startsWith(u8, obj.object_name, "ExitDoor"))
            {
                // ExitDoor ignore width/height/length and just use the predefined one
                const vec = obj.getCenter();
                level.exit_door = .{
                    .x = vec.x,
                    .y = vec.y,
                    .z = vec.z,
                };
            } else {
                std.debug.panic("unhandled object name: {s}, valid: cube, Cube, collect, Collect, player, Player", .{obj.object_name});
                return error.InvalidObjectName;
            }
        }
        // If no spawn, put player on first platform found
        if (!level.player_has_start_position and level.cubes.len > 0) {
            const first_cube = currentLevel.cubes.get(0);
            level.player_start_position = .{
                .x = first_cube.x,
                .y = first_cube.y,
                .z = first_cube.z,
            };
            level.player_has_start_position = true;
        }
        // Set current level to loaded level
        loadedLevel = level;
    }

    // Load textures
    var texGrass: rl.Texture = blk: {
        var img = rl.loadImageFromMemory(".png", @embedFile("resources/textures/tex1.png"));
        // hack: fix textures rendering upside down
        rl.imageFlipVertical(&img);
        defer img.unload();
        break :blk rl.loadTextureFromImage(img);
    };
    defer rl.unloadTexture(texGrass);

    var texSky: rl.Texture = blk: {
        var img = rl.loadImageFromMemory(".png", @embedFile("resources/textures/tex2.png"));
        // hack: fix textures rendering upside down
        rl.imageFlipVertical(&img);
        defer img.unload();
        break :blk rl.loadTextureFromImage(img);
    };
    defer rl.unloadTexture(texSky);

    // Setup collectable mesh/model with default texture
    var collectableMesh = rl.genMeshCube(Collectable.width, Collectable.height, Collectable.length);
    var collectableModel = rl.loadModelFromMesh(collectableMesh);
    collectableModel.materials[0].maps[@intFromEnum(rl.MATERIAL_MAP_DIFFUSE)].texture = texGrass;

    // Limit cursor to relative movement inside the window
    rl.disableCursor();

    // Set our game to run at 120 frames-per-second
    setTargetFPS(120);

    // Reset player
    resetLevel();

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Get rough approximation of current FPS so we can increase how often we simulate
        // each frame
        //
        // This was added as I use software rendering in my browser and noticed the FPS dropped to 30 so
        // I figured I'd keep my determinsitic physics/logic happening but make the game feel better if it's
        // running on a low-end device.
        //
        // I also quickly tested the game on my iPhone 6S in Safari and it gets about 40 FPS.
        // (At time of writing though, I have not added touch inputs so it's unplayable on a phone)
        var fpsBounds = rl.getFPS();
        if (fpsBounds == 0) {
            // GetFPS starts at 0
            fpsBounds = 120;
        }
        if (fpsBounds > 110) {
            fpsBounds = 120;
        } else if (fpsBounds > 50) {
            fpsBounds = 60;
        } else if (fpsBounds > 20) {
            fpsBounds = 30;
        } else if (fpsBounds > 5) {
            fpsBounds = 15;
        }
        const timesToRunUpdateSim: i32 = @divFloor(targetTickRate, fpsBounds);

        // ------------------------------------------------------
        // Update
        // ------------------------------------------------------
        {
            // Update camera rotation outside of sim loop
            {
                const cameraMouseMoveSensitivity: f32 = 0.03;
                var rotation = rl.Vector3.init(0, 0, 0);
                {
                    var mouseDelta = rl.getMouseDelta();
                    if (mouseDelta.x > 0.0) {
                        rotation.x = mouseDelta.x * cameraMouseMoveSensitivity;
                    }
                    if (mouseDelta.x < 0.0) {
                        rotation.x = mouseDelta.x * cameraMouseMoveSensitivity;
                    }
                    if (mouseDelta.y > 0.0) {
                        rotation.y = mouseDelta.y * cameraMouseMoveSensitivity;
                    }
                    if (mouseDelta.y < 0.0) {
                        rotation.y = mouseDelta.y * cameraMouseMoveSensitivity;
                    }
                }
                rl.updateCameraPro(&camera, rl.Vector3.init(0, 0, 0), rotation, 0);
            }

            // Run simulation
            for (0..@intCast(timesToRunUpdateSim)) |_| {
                // Move character
                {
                    const speed: f32 = @TypeOf(player).move_speed;
                    var movement = rl.Vector3.init(0, 0, 0);
                    if (rl.isKeyDown(rl.KeyboardKey.key_w) or rl.isKeyDown(rl.KeyboardKey.key_up)) {
                        movement.x += speed;
                    }
                    if (rl.isKeyDown(rl.KeyboardKey.key_s) or rl.isKeyDown(rl.KeyboardKey.key_down)) {
                        movement.x -= speed;
                    }
                    if (rl.isKeyDown(rl.KeyboardKey.key_a) or rl.isKeyDown(rl.KeyboardKey.key_left)) {
                        movement.y -= speed;
                    }
                    if (rl.isKeyDown(rl.KeyboardKey.key_d) or rl.isKeyDown(rl.KeyboardKey.key_right)) {
                        movement.y += speed;
                    }
                    var new_position = rlx.moveForward(&camera, player.position, movement.x, true);
                    new_position = rlx.moveRight(&camera, new_position, movement.y, true);
                    if (!hasCollisionAtPosition(new_position)) {
                        player.position = new_position;
                    } else {
                        // If has collision, allow the new position if pushed out reasonably
                        const push_out_step: f32 = 0.01; // 1cm
                        const push_out_limit: f32 = 0.05; // 5cm
                        var push_i = push_out_step;
                        while (push_i < push_out_limit and hasCollisionAtPosition(new_position)) : (push_i += push_out_step) {
                            new_position.y += push_out_step;
                        }
                        if (!hasCollisionAtPosition(new_position)) {
                            player.position = new_position;
                        }
                    }
                }

                // Update vspeed
                {
                    var is_on_ground = false;
                    {
                        if (player.vspeed == 0) {
                            var ground_check_position = player.position;
                            ground_check_position.y -= 0.01; // 1cm
                            is_on_ground = hasCollisionAtPosition(ground_check_position);
                        }
                    }

                    // Jump
                    if (player.jumps_since_last_touched_ground < 2 and
                        player.vspeed >= 0 and
                        (rl.isKeyDown(rl.KeyboardKey.key_space) or rl.isMouseButtonPressed(rl.MouseButton.mouse_button_left)))
                    {
                        player.vspeed = @TypeOf(player).jump_power;
                        player.jumps_since_last_touched_ground += 1;
                    }

                    if (!is_on_ground) {
                        player.vspeed += @TypeOf(player).gravity;
                        if (player.vspeed >= 0.32) {
                            player.vspeed = 0.32;
                        }

                        var new_position = player.position;
                        new_position.y -= player.vspeed;
                        if (!hasCollisionAtPosition(new_position)) {
                            player.position = new_position;
                        } else {
                            // If collided, reset fall speed and put inside the ground, then push out
                            player.position = new_position;
                            player.vspeed = 0;
                            player.jumps_since_last_touched_ground = 0;
                            // Push out of ground if colliding
                            while (hasCollisionAtPosition(player.position)) {
                                player.position.y += 0.001; // 0.1cm
                            }
                        }
                    }

                    // If fallen off edge, restart at level start
                    if (player.position.y < -75) {
                        resetLevel();
                    }
                }

                // Grab collectable
                var i: usize = 0;
                while (i < currentLevel.collectables.len) {
                    const collectable = &currentLevel.collectables.slice()[i];
                    if (!rl.checkCollisionBoxSphere(collectable.boundingBox(), player.position, @TypeOf(player).size)) {
                        i += 1; // Only increment if no match
                        continue;
                    }
                    _ = currentLevel.collectables.swapRemove(i);
                    // i += 1; // dont increment as we removed this item
                }

                // Enter exit door
                if (currentLevel.collectables.len == 0) {
                    if (rl.checkCollisionBoxSphere(currentLevel.exit_door.boundingBox(), player.position, @TypeOf(player).size)) {
                        player.has_beaten_level = true;
                    }
                }
            }

            // Update camera after movement
            const isFallingToDeath = player.position.y < -10;
            if (!isFallingToDeath) {
                camera.position = rlx.moveForward(&camera, player.position, -2.75, true);
                camera.position.y += 0.75;
            }
            camera.target = player.position;

            // ignore Y so camera movement work better test
            //camera.target.x = player.position.x;
            //camera.target.z = player.position.z;

            // First person
            // camera.position = rlx.moveForward(&camera, player.position, -0.1, true);
            // camera.position.y += 0.02;
            // camera.target = player.position;
        }

        // ------------------------------------------------------
        // Draw
        // ------------------------------------------------------
        {
            rl.beginDrawing();
            defer rl.endDrawing();

            rl.clearBackground(rl.Color.white);

            {
                rl.beginMode3D(camera);
                defer rl.endMode3D();

                rl.clearBackground(rl.Color.black);

                // draw skybox
                //
                // note(jae): 2023-10-14
                // requires using rlgl.h, so not doing yet
                {
                    // We are inside the cube, we need to disable backface culling!
                    // rl.rlDisableBackfaceCulling();
                    // defer rl.rlEnableBackfaceCulling();
                    // rl.rlDisableDepthMask();
                    // defer rl.rlEnableDepthMask();

                    // rl.drawModel(skybox, rl.Vector3.init(0, 0, 0), 1.0, rl.Color.white);
                }

                // draw player
                rl.drawSphere(player.position, @TypeOf(player).size, rl.Color.red);
                // rl.drawSphereWires(player.position, @TypeOf(player).size, 100, 100, rl.Color.white);

                // draw level
                for (currentLevel.cubes.slice()) |*cube| {
                    var position = rl.Vector3.init(cube.x, cube.y, cube.z);
                    rl.drawCube(
                        position,
                        cube.width,
                        cube.height,
                        cube.length,
                        cube.color,
                    );
                    rl.drawCubeWires(position, cube.width, cube.height, cube.length, rl.Color.white);
                }
                for (currentLevel.collectables.slice()) |*collectable| {
                    var cm = collectableModel;
                    switch (collectable.image) {
                        .Grass => {
                            cm.materials[0].maps[@intFromEnum(rl.MATERIAL_MAP_DIFFUSE)].texture = texGrass;
                        },
                        .Sky => {
                            cm.materials[0].maps[@intFromEnum(rl.MATERIAL_MAP_DIFFUSE)].texture = texSky;
                        },
                    }
                    var position = rl.Vector3.init(collectable.x, collectable.y, collectable.z);
                    collectable.rotate += 0.5 * @as(f32, @floatFromInt(timesToRunUpdateSim));
                    rl.drawModelEx(
                        cm,
                        position,
                        rlx.vector3Normalize(rl.Vector3.init(0, 1, 0)),
                        collectable.rotate,
                        rl.Vector3.init(1, 1, 1),
                        rl.Color.white,
                    );
                    // rl.drawCube(position, collectable.width, collectable.height, collectable.length, collectable.color);
                }
                // Render ExitDoor
                if (currentLevel.collectables.len == 0) {
                    var exit_door = currentLevel.exit_door;
                    {
                        var position = rl.Vector3.init(exit_door.x, exit_door.y, exit_door.z);
                        rl.drawCube(
                            position,
                            ExitDoor.width,
                            ExitDoor.height,
                            ExitDoor.length,
                            rl.Color.purple,
                        );
                    }

                    // Draw the collision around the door
                    const cubes = exit_door.getCubes();
                    for (cubes.slice()) |*cube| {
                        const position = rl.Vector3.init(cube.x, cube.y, cube.z);
                        rl.drawCube(
                            position,
                            cube.width,
                            cube.height,
                            cube.length,
                            cube.color,
                        );
                        rl.drawCubeWires(position, cube.width, cube.height, cube.length, rl.Color.white);
                    }
                }
            }

            // Draw text
            var y: i32 = 16;
            rl.drawText("Welcome to Jae's Hyperreal 3D Generation!", 16, y, 20, rl.Color.light_gray);
            y += 24;
            try rlx.drawTextf("FPS: {}", .{rl.getFPS()}, 16, y, 20, rl.Color.light_gray);
            y += 24;
            try rlx.drawTextf("Player X/Y/Z: {d:.4} {d:.4} {d:.4}", .{ player.position.x, player.position.y, player.position.z }, 16, y, 20, rl.Color.light_gray);

            if (player.has_beaten_level) {
                y += 24;
                rl.drawText("YOU HAVE BEATEN LEVEL", 16, y, 20, rl.Color.light_gray);
            }
        }
    }
}
