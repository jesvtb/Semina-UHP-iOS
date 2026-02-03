# SSE Event Contract

This document describes the SSE event types used by the app, their payload shapes, and how they are routed. The single type for a parsed SSE event is `SSEEvent` (enum in core). Parsing is done in core (`SSEEventType.parse(event:data:id:)`); routing is done in app (`SSEEventRouter.route(_ event:)`).

## Event Types

| Type | Payload Fields | SSEEvent case | Router Delivery |
|------|----------------|---------------|------------------|
| toast | message (string), duration? (number), variant? (string) | `.toast(message, duration, variant)` | ToastManager.show(ToastData) |
| chat | content (string), is_streaming? (bool) | `.chat(chunk, isStreaming)` | ChatManager.handleChatChunk(content, isStreaming) — ChatManager accumulates chunks |
| stop | (none) | `.stop` | ChatManager.handleStop() |
| map | GeoJSON object (e.g. FeatureCollection with "features" or nested in "data"/"result.data") | `.map(features: [[String: JSONValue]])` | MapFeaturesManager.apply(features) |
| hook | action (string) | `.hook(action)` | Router callbacks (e.g. onShowInfoSheet for "show info sheet") |
| content / overview | type (string), data (object) | `.content(typeString, dataValue)` | ContentManager.setContent(type, data) via ContentTypeRegistry.parse |

## Payload JSON Shapes

- **toast**: `{ "message": string, "duration"?: number, "variant"?: string }`
- **chat**: `{ "content": string, "is_streaming"?: boolean }` — each event carries one chunk; ChatManager appends chunks to the current assistant message.
- **stop**: No payload (event type only).
- **map**: GeoJSON object. Supports direct `"features"` array, or nested under `"data"` or `"result"` → `"data"`. Parsed via `GeoJSON.extractFeatures(from:)` in core.
- **hook**: `{ "action": string }`
- **content / overview**: `{ "type": string, "data": object }` — `type` is a ContentViewType raw value; `data` is parsed by ContentTypeRegistry.

## Adding a New Event Type

1. Add a case to `SSEEventType` in core `networking.swift`.
2. Add parsing logic in the `parse(event:data:id:)` switch in core.
3. Add a case to `SSEEvent` (enum) with the appropriate associated values.
4. Add a routing case in `SSEEventRouter.route(_ event:)` in the app.
5. If the event needs a new manager method or callback, add it and wire it in the router.
6. Update this document.

## Architecture Summary

- **Core**: `processSSEStream` parses raw SSE lines (event/data/id), resolves `SSEEventType`, and yields `SSEEvent` (enum) directly via `AsyncThrowingStream<SSEEvent, Error>`. Parsing uses `SSEEventType.parse(event:data:id:)`. Unknown types or parse errors are logged and skipped.
- **App**: `SSEEventProcessor.processStream` consumes the event stream and only calls `router.route(event)`. `SSEEventRouter.route(_ event:)` switches on the `SSEEvent` enum and calls the appropriate manager or callback.
- **Single-event path** (e.g. tests): `processEvent(event:data:id:)` parses raw (event string, data string, id) and routes the resulting `SSEEvent`.
