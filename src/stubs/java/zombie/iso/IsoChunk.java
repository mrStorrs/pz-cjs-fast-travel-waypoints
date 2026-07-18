package zombie.iso;

import java.util.ArrayList;
import zombie.vehicles.BaseVehicle;

public final class IsoChunk {
    public int wx;
    public int wy;
    public final ArrayList<IsoChunkMap> refs = new ArrayList<>();
    public final ArrayList<BaseVehicle> vehicles = new ArrayList<>();
}
