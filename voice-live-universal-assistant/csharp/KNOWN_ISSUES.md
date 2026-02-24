# Known Issues — C# Backend (Azure.AI.VoiceLive 1.1.0-beta.2)

This document tracks known gaps and workarounds in the C# backend implementation.

## 1. Interim Response Not Supported (Medium)

**Issue:** `VoiceLiveSessionOptions` does not expose an `InterimResponse` property in SDK version 1.1.0-beta.2. The underlying types (`LlmInterimResponseConfig`, `StaticInterimResponseConfig`, `InterimResponseTrigger`) are public, but they are not wired to the session options.

**Impact:** Interim response settings from the frontend are silently ignored. The backend logs a warning when this setting is enabled.

**Workaround:** Disable interim response in the frontend settings panel when using the C# backend. This will be resolved when a future SDK version exposes `InterimResponse` as a strongly-typed property on `VoiceLiveSessionOptions`.

## 2. Transcription Model Auto-Correction (Model Mode Only)

**Issue:** Cascaded text models require `azure-speech` as the transcription model, but the frontend may send `gpt-4o-transcribe`.

**Impact:** If left uncorrected, the service returns: *"Only 'azure-speech' and 'mai-ears-1' are supported in cascaded pipelines."*

**Workaround:** The backend auto-corrects `transcribeModel` to `azure-speech` for non-realtime models in model mode. In agent mode, transcription is not sent in the session config (the agent manages its own pipeline). No user action needed — this is handled transparently.
