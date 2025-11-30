# iOS File Storage Guide

## UserDefaults: When to Use It

### ✅ Good for UserDefaults:
- **Small preferences**: Settings, user preferences (< 100 KB)
- **Simple cache**: Small JSON objects, location coordinates
- **App state**: Last viewed screen, user ID, flags
- **Quick access**: Frequently accessed small data

### ❌ NOT for UserDefaults:
- **Large files**: Audio, video, images, documents (> 100 KB)
- **Binary data**: Raw file data
- **User-generated content**: Downloaded files, saved media
- **Large datasets**: Big JSON files, databases

## Current App Usage

Your app currently uses UserDefaults for:
- ✅ Location coordinates (24 bytes) - **Appropriate**
- ✅ Cache metadata (small dictionaries) - **Appropriate**
- ⚠️ Wiki features (could grow large) - **Consider moving to files if > 100 KB**

---

## iOS File Storage Options

### 1. Documents Directory (Recommended for User Files)

**Purpose**: User-visible files that should be backed up and accessible

**Characteristics**:
- ✅ Backed up to iCloud (if enabled)
- ✅ Visible in Files app (if `UIFileSharingEnabled` is set)
- ✅ Persists across app updates
- ✅ User can delete via Files app
- ⚠️ Counts against iCloud storage quota

**Use for**:
- Downloaded audio journeys
- User-saved content
- Documents the user explicitly downloaded
- Files the user should be able to access/manage

**Path**:
```swift
let documentsURL = FileManager.default.urls(for: .documentDirectory, 
                                            in: .userDomainMask)[0]
// Example: /var/mobile/Containers/Data/Application/.../Documents/
```

---

### 2. Caches Directory (Recommended for Temporary Files)

**Purpose**: Cache files that can be re-downloaded

**Characteristics**:
- ❌ NOT backed up to iCloud
- ❌ Can be cleared by system when storage is low
- ✅ Doesn't count against iCloud quota
- ✅ Persists across app launches (until cleared)
- ✅ Best for large files that can be re-downloaded

**Use for**:
- Downloaded audio files (if re-downloadable)
- Image cache
- Large JSON responses
- Any file that can be regenerated/downloaded

**Path**:
```swift
let cachesURL = FileManager.default.urls(for: .cachesDirectory, 
                                        in: .userDomainMask)[0]
// Example: /var/mobile/Containers/Data/Application/.../Library/Caches/
```

---

### 3. Application Support Directory

**Purpose**: App-generated files that should persist

**Characteristics**:
- ✅ Backed up to iCloud
- ✅ Persists across app updates
- ❌ Not visible to user in Files app
- ✅ Good for app data that's not user-visible

**Use for**:
- Database files
- App configuration files
- Generated content that should persist

**Path**:
```swift
let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, 
                                            in: .userDomainMask)[0]
```

---

### 4. Temporary Directory

**Purpose**: Short-lived files

**Characteristics**:
- ❌ Cleared on app restart (or by system)
- ❌ NOT backed up
- ✅ Fast access
- ❌ Can be deleted anytime

**Use for**:
- Processing temporary files
- Files being downloaded (before moving to final location)
- One-time operations

**Path**:
```swift
let tempURL = FileManager.default.temporaryDirectory
// Example: /var/mobile/Containers/Data/Application/.../tmp/
```

---

## Implementation Guide

### File Storage Manager Example

```swift
import Foundation

class FileStorageManager {
    // MARK: - Directory URLs
    
    /// Documents directory - for user-visible files
    static var documentsURL: URL {
        FileManager.default.urls(for: .documentDirectory, 
                                in: .userDomainMask)[0]
    }
    
    /// Caches directory - for re-downloadable files
    static var cachesURL: URL {
        FileManager.default.urls(for: .cachesDirectory, 
                                in: .userDomainMask)[0]
    }
    
    /// Application Support directory - for app data
    static var appSupportURL: URL {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, 
                                          in: .userDomainMask)[0]
        // Create directory if it doesn't exist
        try? FileManager.default.createDirectory(at: url, 
                                                withIntermediateDirectories: true)
        return url
    }
    
    // MARK: - Save Files
    
    /// Save file to Documents directory (user-visible)
    static func saveToDocuments(data: Data, filename: String) throws -> URL {
        let fileURL = documentsURL.appendingPathComponent(filename)
        try data.write(to: fileURL)
        return fileURL
    }
    
    /// Save file to Caches directory (re-downloadable)
    static func saveToCaches(data: Data, filename: String) throws -> URL {
        let fileURL = cachesURL.appendingPathComponent(filename)
        try data.write(to: fileURL)
        return fileURL
    }
    
    // MARK: - Load Files
    
    /// Load file from Documents
    static func loadFromDocuments(filename: String) throws -> Data {
        let fileURL = documentsURL.appendingPathComponent(filename)
        return try Data(contentsOf: fileURL)
    }
    
    /// Load file from Caches
    static func loadFromCaches(filename: String) throws -> Data {
        let fileURL = cachesURL.appendingPathComponent(filename)
        return try Data(contentsOf: fileURL)
    }
    
    // MARK: - Check Existence
    
    static func existsInDocuments(filename: String) -> Bool {
        let fileURL = documentsURL.appendingPathComponent(filename)
        return FileManager.default.fileExists(atPath: fileURL.path)
    }
    
    static func existsInCaches(filename: String) -> Bool {
        let fileURL = cachesURL.appendingPathComponent(filename)
        return FileManager.default.fileExists(atPath: fileURL.path)
    }
    
    // MARK: - Delete Files
    
    static func deleteFromDocuments(filename: String) throws {
        let fileURL = documentsURL.appendingPathComponent(filename)
        try FileManager.default.removeItem(at: fileURL)
    }
    
    static func deleteFromCaches(filename: String) throws {
        let fileURL = cachesURL.appendingPathComponent(filename)
        try FileManager.default.removeItem(at: fileURL)
    }
    
    // MARK: - File Size
    
    static func sizeOfFileInDocuments(filename: String) -> Int64? {
        let fileURL = documentsURL.appendingPathComponent(filename)
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
              let size = attributes[.size] as? Int64 else {
            return nil
        }
        return size
    }
    
    // MARK: - List Files
    
    static func listFilesInDocuments() throws -> [String] {
        let contents = try FileManager.default.contentsOfDirectory(at: documentsURL, 
                                                                  includingPropertiesForKeys: nil)
        return contents.map { $0.lastPathComponent }
    }
    
    static func listFilesInCaches() throws -> [String] {
        let contents = try FileManager.default.contentsOfDirectory(at: cachesURL, 
                                                                   includingPropertiesForKeys: nil)
        return contents.map { $0.lastPathComponent }
    }
    
    // MARK: - Storage Usage
    
    static func totalSizeOfDocuments() -> Int64 {
        guard let contents = try? FileManager.default.contentsOfDirectory(at: documentsURL, 
                                                                          includingPropertiesForKeys: [.fileSizeKey]) else {
            return 0
        }
        
        return contents.reduce(0) { total, url in
            guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else {
                return total
            }
            return total + Int64(size)
        }
    }
    
    static func totalSizeOfCaches() -> Int64 {
        guard let contents = try? FileManager.default.contentsOfDirectory(at: cachesURL, 
                                                                          includingPropertiesForKeys: [.fileSizeKey]) else {
            return 0
        }
        
        return contents.reduce(0) { total, url in
            guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else {
                return total
            }
            return total + Int64(size)
        }
    }
}
```

---

## Download Manager Example

```swift
import Foundation

class DownloadManager {
    /// Download file and save to Caches directory
    static func downloadFile(url: URL, filename: String) async throws -> URL {
        // Download to temporary location first
        let (tempURL, _) = try await URLSession.shared.download(from: url)
        
        // Move to final location in Caches
        let finalURL = FileStorageManager.cachesURL.appendingPathComponent(filename)
        
        // Remove existing file if it exists
        if FileManager.default.fileExists(atPath: finalURL.path) {
            try FileManager.default.removeItem(at: finalURL)
        }
        
        // Move from temp to final location
        try FileManager.default.moveItem(at: tempURL, to: finalURL)
        
        return finalURL
    }
    
    /// Download with progress tracking
    static func downloadFileWithProgress(
        url: URL, 
        filename: String,
        progressHandler: @escaping (Double) -> Void
    ) async throws -> URL {
        let (asyncBytes, _) = try await URLSession.shared.bytes(from: url)
        
        let finalURL = FileStorageManager.cachesURL.appendingPathComponent(filename)
        let fileHandle = try FileHandle(forWritingTo: finalURL)
        defer { try? fileHandle.close() }
        
        var totalBytes: Int64 = 0
        let expectedLength = asyncBytes.response.expectedContentLength
        
        for try await byte in asyncBytes {
            try fileHandle.write(contentsOf: Data([byte]))
            totalBytes += 1
            
            if expectedLength > 0 {
                let progress = Double(totalBytes) / Double(expectedLength)
                progressHandler(progress)
            }
        }
        
        return finalURL
    }
}
```

---

## Recommendations for Your App

### For Audio Journey Downloads:

**Use Caches Directory** because:
- Audio files can be large (MBs)
- They can be re-downloaded if needed
- Don't need to count against iCloud backup
- System can clear if storage is low (user can re-download)

**Example Structure**:
```
Caches/
  └── audio_journeys/
      ├── journey_rome_001.mp3
      ├── journey_paris_002.mp3
      └── journey_tokyo_003.mp3
```

### For User Preferences:

**Keep using UserDefaults** for:
- Last played journey ID
- Playback position (if small)
- User settings

### For Large Cache Data:

**Move to Files** if:
- Wiki features cache > 100 KB per entry
- GeoJSON responses > 100 KB
- Any cache entry > 100 KB

---

## File Size Limits

- **UserDefaults**: ~1 MB per value, ~1-2 MB total
- **File System**: 
  - No hard limit (limited by device storage)
  - iOS can clear Caches directory when storage is low
  - Documents directory persists (backed up)

---

## Best Practices

1. **Ask user permission** before downloading large files
2. **Show download progress** for files > 1 MB
3. **Handle storage errors** gracefully
4. **Clean up old files** periodically
5. **Check available storage** before downloading
6. **Use appropriate directory** based on file purpose

---

## Checking Available Storage

```swift
func checkAvailableStorage() -> Int64? {
    guard let attributes = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory()),
          let freeSize = attributes[.systemFreeSize] as? Int64 else {
        return nil
    }
    return freeSize
}

// Usage:
if let freeSpace = checkAvailableStorage(), freeSpace < 100 * 1024 * 1024 {
    // Less than 100 MB free
    print("⚠️ Low storage: \(freeSpace / 1024 / 1024) MB available")
}
```



