package zombie.vehicles;

import zombie.core.physics.Transform;

public class BaseVehicle {
    public static Transform allocTransform() {
        throw new AssertionError("compile-only stub");
    }

    public static void releaseTransform(Transform transform) {
        throw new AssertionError("compile-only stub");
    }

    public Transform getWorldTransform(Transform transform) {
        throw new AssertionError("compile-only stub");
    }

    public void setWorldTransform(Transform transform) {
        throw new AssertionError("compile-only stub");
    }

    public float getX() {
        throw new AssertionError("compile-only stub");
    }

    public float getY() {
        throw new AssertionError("compile-only stub");
    }
}
