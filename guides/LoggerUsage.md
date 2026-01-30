# Logger Usage Guide

## Overview

All services now use a **shared logger instance** from `AppLifecycleManager` for consistent logging across the app. The logger stores all log entries in memory for retrieval. The logger implementation is provided by `core.InMemoryLogger` from the core module.

## Why Shared Logger?

1. **Consistency**: All services log to the same place
2. **Full Records**: All logs are stored and can be retrieved
3. **Efficiency**: Single logger instance instead of multiple instances
4. **Centralized**: Easy to add features like file logging or crash reporting

## Default Behavior

All services automatically use the shared logger by default:

```swift
// All these use the shared logger automatically
let trackingManager = TrackingManager()
let addrSearchManager = AddressSearchManager()
let apiClient = APIClient()
let processor = SSEEventProcessor(handler: router)
```

## Accessing Log Records

### Get All Logs

```swift
// Get all log entries as an array
let allLogs = AppLifecycleManager.sharedLogger.allLogs

// Get formatted log string
let formattedLogs = AppLifecycleManager.sharedLogger.formattedLogs
print(formattedLogs)
```

### Example: View Logs in Debug Menu

```swift
struct DebugLogView: View {
    var body: some View {
        ScrollView {
            Text(AppLifecycleManager.sharedLogger.formattedLogs)
                .font(.system(.caption, design: .monospaced))
                .padding()
        }
        .navigationTitle("App Logs")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Clear") {
                    AppLifecycleManager.sharedLogger.clearLogs()
                }
            }
        }
    }
}
```

### Log Entry Structure

The logger uses `core.LogEntry` and `core.LogLevel` from the core module:

```swift
// From core module
public struct LogEntry {
    let timestamp: Date      // When the log was created
    let level: LogLevel      // .debug, .info, .warning, or .error
    let message: String       // The log message
    let handlerType: String?  // Which service logged it (e.g., "TrackingManager")
    let error: String?       // Error description if applicable
}

public enum LogLevel {
    case debug
    case info
    case warning
    case error
}
```

Note: `AppLifecycleManager.sharedLogger` returns `core.InMemoryLogger.shared`, which provides the log storage functionality.

### Filter Logs

```swift
// Get only error logs
let errorLogs = AppLifecycleManager.sharedLogger.allLogs
    .filter { $0.level == .error }

// Get logs from a specific service
let trackingLogs = AppLifecycleManager.sharedLogger.allLogs
    .filter { $0.handlerType == "TrackingManager" }

// Get logs from last hour
let oneHourAgo = Date().addingTimeInterval(-3600)
let recentLogs = AppLifecycleManager.sharedLogger.allLogs
    .filter { $0.timestamp > oneHourAgo }
```

## Log Storage

- **Capacity**: Stores up to 1000 most recent log entries (automatically removes oldest)
- **Thread-Safe**: Safe to access from any thread
- **Memory**: Stored in memory (not persisted to disk by default)

## Custom Logger for Testing

You can still inject a custom logger for testing. Custom loggers must conform to `core.Logger`:

```swift
// In tests
import core

class MockLogger: Logger {
    var debugMessages: [String] = []
    var errorMessages: [String] = []
    
    func debug(_ message: String) {
        debugMessages.append(message)
    }
    
    func error(_ message: String, handlerType: String?, error: Error?) {
        errorMessages.append(message)
    }
    
    func warning(_ message: String, handlerType: String?) {
        // ...
    }
    
    func info(_ message: String) {
        // ...
    }
}

let mockLogger = MockLogger()
let trackingManager = TrackingManager(logger: mockLogger)
```

## Future Enhancements

Potential additions:
- File-based logging for persistence
- Log export (email, share sheet)
- Integration with crash reporting services (Sentry, Firebase)
- Log levels filtering
- Remote logging for production debugging
