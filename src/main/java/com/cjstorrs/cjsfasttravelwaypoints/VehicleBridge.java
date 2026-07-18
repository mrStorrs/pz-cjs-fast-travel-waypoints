package com.cjstorrs.cjsfasttravelwaypoints;

import se.krka.kahlua.integration.annotations.LuaMethod;
import zombie.core.physics.Transform;
import zombie.vehicles.BaseVehicle;

public final class VehicleBridge {
    private VehicleBridge() {
    }

    @LuaMethod(name = "cjsFastTravelSetVehicleWorldPosition", global = true)
    public static boolean setVehicleWorldPosition(BaseVehicle vehicle, double destinationX, double destinationY) {
        if (vehicle == null || !Double.isFinite(destinationX) || !Double.isFinite(destinationY)) {
            return false;
        }

        Transform transform = BaseVehicle.allocTransform();
        try {
            vehicle.getWorldTransform(transform);
            transform.origin.x += (float)(destinationX - vehicle.getX());
            transform.origin.z += (float)(destinationY - vehicle.getY());
            vehicle.setWorldTransform(transform);
            return true;
        } finally {
            BaseVehicle.releaseTransform(transform);
        }
    }
}
