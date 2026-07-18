package com.cjstorrs.cjsfasttravelwaypoints;

import java.lang.annotation.Annotation;
import java.lang.reflect.Field;
import java.lang.reflect.Method;
import java.lang.reflect.Modifier;

public final class GameApiLinkageTest {
    private GameApiLinkageTest() {
    }

    public static void main(String[] args) throws ReflectiveOperationException {
        ClassLoader loader = GameApiLinkageTest.class.getClassLoader();
        Class<?> baseVehicle = Class.forName("zombie.vehicles.BaseVehicle", false, loader);
        Class<?> transform = Class.forName("zombie.core.physics.Transform", false, loader);
        Class<?> bullet = Class.forName("zombie.core.physics.Bullet", false, loader);
        Class<?> vector3f = Class.forName("org.joml.Vector3f", false, loader);
        Class<?> isoChunk = Class.forName("zombie.iso.IsoChunk", false, loader);
        Class<?> isoChunkMap = Class.forName("zombie.iso.IsoChunkMap", false, loader);
        Class<?> isoGridSquare = Class.forName("zombie.iso.IsoGridSquare", false, loader);
        Class<?> chunkSaveWorker = Class.forName("zombie.iso.ChunkSaveWorker", false, loader);

        Method allocTransform = baseVehicle.getMethod("allocTransform");
        check(Modifier.isStatic(allocTransform.getModifiers()), "BaseVehicle.allocTransform must remain static");
        check(allocTransform.getReturnType() == transform, "BaseVehicle.allocTransform return type changed");

        Method releaseTransform = baseVehicle.getMethod("releaseTransform", transform);
        check(Modifier.isStatic(releaseTransform.getModifiers()), "BaseVehicle.releaseTransform must remain static");
        check(releaseTransform.getReturnType() == void.class, "BaseVehicle.releaseTransform return type changed");

        Method getWorldTransform = baseVehicle.getMethod("getWorldTransform", transform);
        check(getWorldTransform.getReturnType() == transform, "BaseVehicle.getWorldTransform return type changed");
        check(baseVehicle.getMethod("setWorldTransform", transform).getReturnType() == void.class,
            "BaseVehicle.setWorldTransform return type changed");
        check(baseVehicle.getMethod("getX").getReturnType() == float.class, "BaseVehicle.getX return type changed");
        check(baseVehicle.getMethod("getY").getReturnType() == float.class, "BaseVehicle.getY return type changed");
        check(baseVehicle.getField("vehicleId").getType() == short.class, "BaseVehicle.vehicleId type changed");
        check(baseVehicle.getField("jniLinearVelocity").getType() == vector3f,
            "BaseVehicle.jniLinearVelocity type changed");
        check(baseVehicle.getMethod("setSpeedKmHour", float.class).getReturnType() == void.class,
            "BaseVehicle.setSpeedKmHour signature changed");
        check(vector3f.getMethod("set", float.class, float.class, float.class).getReturnType() == vector3f,
            "Vector3f.set(float, float, float) signature changed");
        check(bullet.getMethod("getOwnVehiclePhysics", int.class, float[].class).getReturnType() == int.class,
            "Bullet.getOwnVehiclePhysics signature changed");
        check(bullet.getMethod("setOwnVehiclePhysics", int.class, float[].class, boolean.class).getReturnType() == int.class,
            "Bullet.setOwnVehiclePhysics signature changed");

        Field origin = transform.getField("origin");
        check(origin.getType() == vector3f, "Transform.origin type changed");
        check(Modifier.isFinal(origin.getModifiers()), "Transform.origin must remain final");
        check(vector3f.getField("x").getType() == float.class, "Vector3f.x type changed");
        check(vector3f.getField("z").getType() == float.class, "Vector3f.z type changed");

        check(baseVehicle.getField("chunk").getType() == isoChunk, "BaseVehicle.chunk type changed");
        check(baseVehicle.getMethod("getSquare").getReturnType() == isoGridSquare,
            "BaseVehicle.getSquare return type changed");
        check(isoGridSquare.getMethod("getChunk").getReturnType() == isoChunk,
            "IsoGridSquare.getChunk return type changed");

        Field refs = isoChunk.getField("refs");
        check(refs.getType() == java.util.ArrayList.class, "IsoChunk.refs type changed");
        check(Modifier.isFinal(refs.getModifiers()), "IsoChunk.refs must remain final");
        Field vehicles = isoChunk.getField("vehicles");
        check(vehicles.getType() == java.util.ArrayList.class, "IsoChunk.vehicles type changed");
        check(Modifier.isFinal(vehicles.getModifiers()), "IsoChunk.vehicles must remain final");
        check(isoChunk.getField("wx").getType() == int.class, "IsoChunk.wx type changed");
        check(isoChunk.getField("wy").getType() == int.class, "IsoChunk.wy type changed");
        check(isoChunkMap.getField("ignore").getType() == boolean.class, "IsoChunkMap.ignore type changed");
        check(isoChunkMap.getField("SharedChunks").getType() == java.util.HashMap.class,
            "IsoChunkMap.SharedChunks type changed");
        check(chunkSaveWorker.getField("instance").getType() == chunkSaveWorker,
            "ChunkSaveWorker.instance type changed");
        check(chunkSaveWorker.getMethod("Add", isoChunk).getReturnType() == void.class,
            "ChunkSaveWorker.Add signature changed");

        Class<?> bridge = Class.forName(
            "com.cjstorrs.cjsfasttravelwaypoints.VehicleBridge",
            false,
            loader
        );
        Method move = bridge.getMethod("setVehicleWorldPosition", baseVehicle, double.class, double.class);
        check(Modifier.isPublic(move.getModifiers()) && Modifier.isStatic(move.getModifiers()),
            "VehicleBridge.setVehicleWorldPosition must remain public and static");
        check(move.getReturnType() == boolean.class, "VehicleBridge.setVehicleWorldPosition return type changed");
        checkGlobalLuaMethod(move, "cjsFastTravelSetVehicleWorldPosition");

        Method clearVelocity = bridge.getMethod("clearVehicleLinearVelocity", baseVehicle);
        check(clearVelocity.getReturnType() == boolean.class,
            "VehicleBridge.clearVehicleLinearVelocity return type changed");
        checkGlobalLuaMethod(clearVelocity, "cjsFastTravelClearVehicleLinearVelocity");

        Method getVehicleChunk = bridge.getMethod("getVehicleChunk", baseVehicle);
        check(getVehicleChunk.getReturnType() == isoChunk, "VehicleBridge.getVehicleChunk return type changed");
        checkGlobalLuaMethod(getVehicleChunk, "cjsFastTravelGetVehicleChunk");

        Method getChunkRefs = bridge.getMethod("getChunkRefs", isoChunk);
        check(getChunkRefs.getReturnType() == java.util.ArrayList.class,
            "VehicleBridge.getChunkRefs return type changed");
        checkGlobalLuaMethod(getChunkRefs, "cjsFastTravelGetChunkRefs");

        Method getChunkVehicles = bridge.getMethod("getChunkVehicles", isoChunk);
        check(getChunkVehicles.getReturnType() == java.util.ArrayList.class,
            "VehicleBridge.getChunkVehicles return type changed");
        checkGlobalLuaMethod(getChunkVehicles, "cjsFastTravelGetChunkVehicles");

        Method getChunkWx = bridge.getMethod("getChunkWx", isoChunk);
        check(getChunkWx.getReturnType() == int.class, "VehicleBridge.getChunkWx return type changed");
        checkGlobalLuaMethod(getChunkWx, "cjsFastTravelGetChunkWx");

        Method getChunkWy = bridge.getMethod("getChunkWy", isoChunk);
        check(getChunkWy.getReturnType() == int.class, "VehicleBridge.getChunkWy return type changed");
        checkGlobalLuaMethod(getChunkWy, "cjsFastTravelGetChunkWy");

        Method isChunkMapIgnored = bridge.getMethod("isChunkMapIgnored", isoChunkMap);
        check(isChunkMapIgnored.getReturnType() == boolean.class,
            "VehicleBridge.isChunkMapIgnored return type changed");
        checkGlobalLuaMethod(isChunkMapIgnored, "cjsFastTravelIsChunkMapIgnored");

        Method removeSharedChunk = bridge.getMethod("removeSharedChunk", int.class);
        check(removeSharedChunk.getReturnType() == void.class,
            "VehicleBridge.removeSharedChunk return type changed");
        checkGlobalLuaMethod(removeSharedChunk, "cjsFastTravelRemoveSharedChunk");

        Method queueChunkSave = bridge.getMethod("queueChunkSave", isoChunk);
        check(queueChunkSave.getReturnType() == void.class,
            "VehicleBridge.queueChunkSave return type changed");
        checkGlobalLuaMethod(queueChunkSave, "cjsFastTravelQueueChunkSave");

        bridge.getDeclaredConstructor();
        Class<?> exposer = Class.forName("me.zed_0xff.zombie_buddy.Exposer", false, loader);
        Method hasGlobalLuaMethod = exposer.getMethod("hasGlobalLuaMethod", Class.class);
        check(Boolean.TRUE.equals(hasGlobalLuaMethod.invoke(null, bridge)),
            "ZombieBuddy did not recognize the vehicle bridge's global Lua method");
    }

    private static void checkGlobalLuaMethod(Method method, String expectedName) throws ReflectiveOperationException {
        check(Modifier.isPublic(method.getModifiers()) && Modifier.isStatic(method.getModifiers()),
            method.getName() + " must remain public and static");
        Annotation luaMethod = findAnnotation(method, "se.krka.kahlua.integration.annotations.LuaMethod");
        check(luaMethod != null, method.getName() + " LuaMethod annotation is missing");
        Method name = luaMethod.annotationType().getMethod("name");
        Method global = luaMethod.annotationType().getMethod("global");
        check(expectedName.equals(name.invoke(luaMethod)), method.getName() + " Lua function name changed");
        check(Boolean.TRUE.equals(global.invoke(luaMethod)), method.getName() + " Lua function must remain global");
    }

    private static Annotation findAnnotation(Method method, String className) {
        for (Annotation annotation : method.getDeclaredAnnotations()) {
            if (className.equals(annotation.annotationType().getName())) {
                return annotation;
            }
        }
        return null;
    }

    private static void check(boolean condition, String message) {
        if (!condition) {
            throw new AssertionError(message);
        }
    }
}
