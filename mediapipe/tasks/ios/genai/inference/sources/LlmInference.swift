// Copyright 2024 The MediaPipe Authors.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import Foundation
import LlmInferenceEngineC
import LlmTaskRunner

/// A MediaPipe task that performs inference using a given Large Language Model.
@objc(MPPLlmInference) public final class LlmInference: NSObject {
  private static let numberOfDecodeStepsPerSync = 3
  private static let sequenceBatchSize = 0

  private let llmTaskRunner: LlmTaskRunner

  /// Creates a new instance of `LlmInference` with the option.
  ///
  /// - Parameters:
  ///   - options: The options of type `LlmInference.Options` to use for configuring the
  /// `LlmInference`.
  @objc public init(options: Options) {
    let modelPath = strdup(options.modelPath)
    let cacheDirectory = strdup(FileManager.default.temporaryDirectory.path)

    defer {
      free(modelPath)
      free(cacheDirectory)
    }

    let sessionConfig = LlmSessionConfig(
      model_path: modelPath,
      cache_dir: cacheDirectory,
      sequence_batch_size: LlmInference.sequenceBatchSize,
      num_decode_steps_per_sync: LlmInference.numberOfDecodeStepsPerSync,
      max_sequence_length: options.maxSequenceLength,
      topk: options.topk,
      temperature: options.temperature,
      random_seed: options.randomSeed)
    llmTaskRunner = LlmTaskRunner(sessionConfig: sessionConfig)

    super.init()
  }

  /// A convenience initializer that creates a new instance of `LlmInference` from an absolute path
  /// to a model asset bundle stored locally on the device and the default `LlmInference.Options`.
  ///
  /// - Parameters:
  ///   - modelPath: The absolute path to a model asset bundle stored locally on the device.
  @objc public convenience init(modelPath: String) {
    let options = Options(modelPath: modelPath)
    self.init(options: options)
  }

  /// Generates a response based on the input text.
  ///
  /// - Parameters:
  ///   - inputText: A `String` that is used to query the LLM.
  /// - Throws: An error if the LLM's response is invalid.
  @objc public func generateResponse(inputText: String) throws -> String {
    let tokens = try llmTaskRunner.predict(inputText: inputText)
    guard let humanReadableLlmResponse = LlmInference.humanReadableString(llmResponses: tokens)
    else {
      throw LlmInferenceError.invalidResponseError
    }

    return humanReadableLlmResponse
  }

  private static func humanReadableString(
    llmResponses: [String], stripLeadingWhitespaces: Bool = true
  ) -> String? {
    guard let llmResponse = llmResponses.first else {
      return nil
    }
    return llmResponse.humanReadableString(stripLeadingWhitespaces: stripLeadingWhitespaces)
  }

}

// Extension to `LlmInference` for defining `LlmInference.Options`
extension LlmInference {
  /// Options for setting up a `LlmInference`.
  @objc(MPPLlmInferenceOptions) public final class Options: NSObject {
    /// The absolute path to the model asset bundle stored locally on the device.
    @objc public var modelPath: String

    /// The total length of the kv-cache. In other words, this is the total number of input + output
    /// tokens the model needs to handle.
    @objc public var maxSequenceLength: Int

    /// The top K number of tokens to be sampled from for each decoding step. A value of 1 means
    /// greedy decoding. Defaults to 40.
    @objc public var topk: Int

    /// The randomness when decoding the next token. A value of 0.0f means greedy decoding. Defaults
    /// to 0.8.
    @objc public var temperature: Float

    /// The random seed for sampling tokens.
    @objc public var randomSeed: Int

    /// Creates a new instance of `Options` with the modelPath and default values of
    /// `maxSequenceLength`, `topK``, `temperature` and `randomSeed`.
    /// This function is only intended to be used from Objective C.
    ///
    /// - Parameters:
    ///   - modelPath: The absolute path to a model asset bundle stored locally on the device.
    @available(swift, obsoleted: 1.0)
    @objc public convenience init(modelPath: String) {
      self.init(modelPath: modelPath)
    }

    /// Creates a new instance of `Options` with the given values.
    ///
    /// - Parameters:
    ///   - modelPath: The absolute path to a model asset bundle stored locally on the device.
    ///   - maxSequenceLength: The total number of input + output tokens the model needs to handle
    ///     (total length of the kv-cache).
    ///   - topk: The top K number of tokens to be sampled from for each decoding step.
    ///   - temperature: The randomness when decoding the next token.
    ///   - randomSeed: The random seed for sampling tokens.
    public init(
      modelPath: String,
      maxSequenceLength: Int = 512,
      topk: Int = 40,
      temperature:
        Float = 0.8,
      randomSeed: Int = 0
    ) {
      self.modelPath = modelPath
      self.maxSequenceLength = maxSequenceLength
      self.topk = topk
      self.temperature = temperature
      self.randomSeed = randomSeed
      super.init()
    }
  }
}

/// An extension to `String` to add some utility functions.
extension String {
  private static let tokenSplitter = "▁"  // Note this is NOT an underscore: ▁(U+2581)
  private static let newLine = "<0x0A>"
  private static let eod = "\\[eod\\]"

  fileprivate func humanReadableString(stripLeadingWhitespaces: Bool = true) -> String? {
    var humanReadableString = self.replacingOccurrences(of: String.tokenSplitter, with: " ")
      .replacingOccurrences(of: String.newLine, with: "\n")
    humanReadableString =
      stripLeadingWhitespaces
      ? humanReadableString.trimmingCharacters(in: .whitespaces) : humanReadableString
    return humanReadableString.components(separatedBy: String.eod).first
  }
}
