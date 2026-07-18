package com.cjstorrs.cjsfasttravelwaypoints;

import java.util.ArrayList;
import se.krka.kahlua.integration.annotations.LuaMethod;
import zombie.core.physics.Transform;
import zombie.iso.ChunkSaveWorker;
import zombie.iso.IsoChunk;
import zombie.iso.IsoChunkMap;
import zombie.iso.IsoGridSquare;
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

    @LuaMethod(name = "cjsFastTravelGetVehicleChunk", global = true)
    public static IsoChunk getVehicleChunk(BaseVehicle vehicle) {
        if (vehicle == null) {
            return null;
        }
        if (vehicle.chunk != null) {
            return vehicle.chunk;
        }

        IsoGridSquare square = vehicle.getSquare();
        return square == null ? null : square.getChunk();
    }

    @LuaMethod(name = "cjsFastTravelGetChunkRefs", global = true)
    public static ArrayList<IsoChunkMap> getChunkRefs(IsoChunk chunk) {
        return chunk == null ? null : chunk.refs;
    }

    @LuaMethod(name = "cjsFastTravelGetChunkVehicles", global = true)
    public static ArrayList<BaseVehicle> getChunkVehicles(IsoChunk chunk) {
        return chunk == null ? null : chunk.vehicles;
    }

    @LuaMethod(name = "cjsFastTravelGetChunkWx", global = true)
    public static int getChunkWx(IsoChunk chunk) {
        return chunk == null ? 0 : chunk.wx;
    }

    @LuaMethod(name = "cjsFastTravelGetChunkWy", global = true)
    public static int getChunkWy(IsoChunk chunk) {
        return chunk == null ? 0 : chunk.wy;
    }

    @LuaMethod(name = "cjsFastTravelIsChunkMapIgnored", global = true)
    public static boolean isChunkMapIgnored(IsoChunkMap chunkMap) {
        return chunkMap != null && chunkMap.ignore;
    }

    @LuaMethod(name = "cjsFastTravelRemoveSharedChunk", global = true)
    public static void removeSharedChunk(int sharedKey) {
        IsoChunkMap.SharedChunks.remove(sharedKey);
    }

    @LuaMethod(name = "cjsFastTravelQueueChunkSave", global = true)
    public static void queueChunkSave(IsoChunk chunk) {
        if (chunk != null) {
            ChunkSaveWorker.instance.Add(chunk);
        }
    }
}
