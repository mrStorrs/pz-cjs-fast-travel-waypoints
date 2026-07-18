package zombie.iso;

import java.util.HashMap;

public final class IsoChunkMap {
    public static final HashMap<Integer, IsoChunk> SharedChunks = new HashMap<>();
    public boolean ignore;
}
