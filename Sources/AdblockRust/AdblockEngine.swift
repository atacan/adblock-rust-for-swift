import CAdblockRust
import Foundation

public enum AdblockRustError: Error, LocalizedError {
  case invalidUTF8
  case engineCreationFailed(String)
  case contentBlockerConversionFailed(String)
  case serializationFailed

  public var errorDescription: String? {
    switch self {
    case .invalidUTF8:
      return "Input was not valid UTF-8."
    case .engineCreationFailed(let message):
      return message
    case .contentBlockerConversionFailed(let message):
      return message
    case .serializationFailed:
      return "The engine did not return serialized data."
    }
  }
}

public final class AdblockEngine {
  public enum ResourceType: String {
    case document
    case subdocument
    case script
    case image
    case stylesheet
    case xmlhttprequest
    case media
    case font
    case other
  }

  public struct MatchResult: Sendable {
    public let matched: Bool
    public let important: Bool
    public let hasException: Bool
    public let redirect: String?
    public let rewrittenURL: String?
  }

  public struct ContentBlockingRules: Sendable {
    public let json: String
    public let truncated: Bool
  }

  private let raw: OpaquePointer

  public init() {
    raw = abr_engine_new()
  }

  public init(rules: String) throws {
    var error: UnsafeMutablePointer<CChar>?
    let engine = rules.utf8CString.withUnsafeBufferPointer { buffer in
      abr_engine_from_rules(
        UnsafeRawPointer(buffer.baseAddress!).assumingMemoryBound(to: UInt8.self),
        max(buffer.count - 1, 0),
        &error
      )
    }
    guard let engine else {
      let message = Self.takeString(error) ?? "Failed to create adblock engine."
      throw AdblockRustError.engineCreationFailed(message)
    }
    raw = engine
  }

  public init(serializedData: Data) throws {
    var error: UnsafeMutablePointer<CChar>?
    let engine = serializedData.withUnsafeBytes { bytes in
      abr_engine_from_serialized(
        bytes.bindMemory(to: UInt8.self).baseAddress,
        bytes.count,
        &error
      )
    }
    guard let engine else {
      let message = Self.takeString(error) ?? "Failed to deserialize adblock engine."
      throw AdblockRustError.engineCreationFailed(message)
    }
    raw = engine
  }

  deinit {
    abr_engine_destroy(raw)
  }

  public func match(
    url: String,
    hostname: String,
    sourceHostname: String,
    resourceType: ResourceType,
    thirdParty: Bool,
    previouslyMatchedRule: Bool = false,
    forceCheckExceptions: Bool = false
  ) -> MatchResult {
    let result = url.withCString { urlPointer in
      hostname.withCString { hostnamePointer in
        sourceHostname.withCString { sourcePointer in
          resourceType.rawValue.withCString { resourceTypePointer in
            abr_engine_matches(
              raw,
              urlPointer,
              hostnamePointer,
              sourcePointer,
              resourceTypePointer,
              thirdParty,
              previouslyMatchedRule,
              forceCheckExceptions
            )
          }
        }
      }
    }

    defer { abr_match_result_destroy(result) }
    return MatchResult(
      matched: result.matched,
      important: result.important,
      hasException: result.has_exception,
      redirect: Self.string(result.redirect),
      rewrittenURL: Self.string(result.rewritten_url)
    )
  }

  public func shouldBlock(
    requestURL: URL,
    sourceURL: URL,
    resourceType: ResourceType,
    aggressive: Bool = false
  ) -> Bool {
    guard requestURL.scheme != "data",
      let requestHost = requestURL.host,
      let sourceHost = sourceURL.host
    else {
      return false
    }

    let thirdParty = requestHost != sourceHost
    if !aggressive && !thirdParty {
      return false
    }

    return match(
      url: requestURL.absoluteString,
      hostname: requestHost,
      sourceHostname: sourceHost,
      resourceType: resourceType,
      thirdParty: thirdParty
    ).matched
  }

  public func serialize() throws -> Data {
    let buffer = abr_engine_serialize(raw)
    defer { abr_free_byte_buffer(buffer) }
    guard let data = buffer.data, buffer.len > 0 else {
      throw AdblockRustError.serializationFailed
    }
    return Data(bytes: data, count: buffer.len)
  }

  public static func contentBlockingRules(fromFilterSet rules: String) throws
    -> ContentBlockingRules
  {
    let result = rules.utf8CString.withUnsafeBufferPointer { buffer in
      abr_content_blocking_rules_from_filter_set(
        UnsafeRawPointer(buffer.baseAddress!).assumingMemoryBound(to: UInt8.self),
        max(buffer.count - 1, 0)
      )
    }
    defer { abr_content_blocking_rules_result_destroy(result) }

    guard result.ok else {
      let message = Self.string(result.error_message)
        ?? "Failed to convert rules to content-blocking JSON."
      throw AdblockRustError.contentBlockerConversionFailed(message)
    }
    return ContentBlockingRules(
      json: Self.string(result.rules_json) ?? "[]",
      truncated: result.truncated
    )
  }

  private static func string(_ pointer: UnsafeMutablePointer<CChar>?) -> String? {
    guard let pointer else { return nil }
    let value = String(cString: pointer)
    return value.isEmpty ? nil : value
  }

  private static func takeString(_ pointer: UnsafeMutablePointer<CChar>?) -> String? {
    defer { abr_free_string(pointer) }
    return string(pointer)
  }
}
