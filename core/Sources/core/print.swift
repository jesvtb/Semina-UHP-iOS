import Foundation

func printItem(item: Any, heading: String) {
    print("================")
    print("🔹 \(heading) (\(type(of: item))): \n   \(item)\n")
    print("================")
}

func printItem(item: Any) {
    print("================")
    print("🔹 type: \(type(of: item)) \n   \(item)")
    print("================")
}

/// Pretty-prints JSONValue or Optional<JSONValue>. Labeled as "parsed data" so it’s distinct from printItem(SSEEvent). Handles both JSONValue and JSONValue?.
func printItem(item: JSONValue?, heading: String = "parsed data (JSONValue)") {
    guard let value = item else {
        print("================")
        print("🔹 \(heading) (Optional<JSONValue>) \n   nil")
        print("================")
        return
    }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
    guard let jsonData = try? encoder.encode(value),
          let jsonString = String(data: jsonData, encoding: .utf8) else {
        return
    }
    print("================")
    print("🔹 \(heading) (JSONValue)\n\(jsonString)")
    print("================")
}

func printItem(item: Data) {
    let jsonValue = try? item.shapeIntoJsonValue()
}

/// Pretty-prints a Dictionary of JSONValue.
func printItem(item: [String: JSONValue], heading: String = "parsed data (JSONValue)") {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
    guard let jsonData = try? encoder.encode(item),
          let jsonString = String(data: jsonData, encoding: .utf8) else {
        print("================")
        print("🔹 \(heading) (Optional<[String: JSONValue]>) \n   nil")
        print("================") 
        return
    }
    print("================")
    print("🔹 \(heading) ([String: JSONValue])\n\(jsonString)")
    print("================")
}

/// Pretty-prints an SSEEvent (typed enum) with case and associated values.
func printItem(item: SSEEvent) {
    print("================")
    print("🔹 type: SSEEvent (enum)")
    switch item {
    case .toast(let message, let duration, let variant):
        print("   case: toast")
        print("   message: \(message)")
        print("   duration: \(String(describing: duration))")
        print("   variant: \(String(describing: variant))")
    case .chat(let chatId, let chunk, let isStreaming):
        print("   case: chat")
        print("   chatId: \(String(describing: chatId))")
        print("   chunk: \(chunk)")
        print("   isStreaming: \(isStreaming)")
    case .stop:
        print("   case: stop")
    case .map(let features):
        print("   case: map")
        print("   features.count: \(features.count)")
    case .hook(let action):
        print("   case: hook")
        print("   action: \(action)")
    case .catalogue(let typeString, let dataValue):
        print("   case: catalogue")
        print("   typeString: \(typeString)")
        let catalogueEncoder = JSONEncoder()
        catalogueEncoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        if let jsonData = try? catalogueEncoder.encode(dataValue),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            print("   dataValue:\n\(jsonString)")
        } else {
            print("   dataValue: \(dataValue)")
        }
    }
    print("================")
}