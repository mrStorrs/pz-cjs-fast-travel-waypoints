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
        Class<?> vector3f = Class.forName("org.joml.Vector3f", false, loader);

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

        Field origin = transform.getField("origin");
        check(origin.getType() == vector3f, "Transform.origin type changed");
        check(Modifier.isFinal(origin.getModifiers()), "Transform.origin must remain final");
        check(vector3f.getField("x").getType() == float.class, "Vector3f.x type changed");
        check(vector3f.getField("z").getType() == float.class, "Vector3f.z type changed");

        Class<?> bridge = Class.forName(
            "com.cjstorrs.cjsfasttravelwaypoints.VehicleBridge",
            false,
            loader
        );
        Method move = bridge.getMethod("setVehicleWorldPosition", baseVehicle, double.class, double.class);
        check(Modifier.isPublic(move.getModifiers()) && Modifier.isStatic(move.getModifiers()),
            "VehicleBridge.setVehicleWorldPosition must remain public and static");
        check(move.getReturnType() == boolean.class, "VehicleBridge.setVehicleWorldPosition return type changed");

        Annotation luaMethod = findAnnotation(move, "se.krka.kahlua.integration.annotations.LuaMethod");
        check(luaMethod != null, "VehicleBridge LuaMethod annotation is missing");
        Method name = luaMethod.annotationType().getMethod("name");
        Method global = luaMethod.annotationType().getMethod("global");
        check("cjsFastTravelSetVehicleWorldPosition".equals(name.invoke(luaMethod)),
            "VehicleBridge Lua function name changed");
        check(Boolean.TRUE.equals(global.invoke(luaMethod)), "VehicleBridge Lua function must remain global");

        bridge.getDeclaredConstructor();
        Class<?> exposer = Class.forName("me.zed_0xff.zombie_buddy.Exposer", false, loader);
        Method hasGlobalLuaMethod = exposer.getMethod("hasGlobalLuaMethod", Class.class);
        check(Boolean.TRUE.equals(hasGlobalLuaMethod.invoke(null, bridge)),
            "ZombieBuddy did not recognize the vehicle bridge's global Lua method");
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
