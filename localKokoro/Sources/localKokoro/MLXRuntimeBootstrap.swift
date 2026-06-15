import Foundation
import MLX

public enum MLXRuntimeBootstrap {
    public static func configureIfNeeded() {
        GPU.set(cacheLimit: 50 * 1024 * 1024)
        GPU.set(memoryLimit: 900 * 1024 * 1024)
    }
}
