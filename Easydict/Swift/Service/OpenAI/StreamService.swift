//
//  StreamService.swift
//  Easydict
//
//  Created by tisfeng on 2024/5/20.
//  Copyright © 2024 izual. All rights reserved.
//

import Combine
import Defaults
import Foundation
import OpenAI
import SwiftUI

// MARK: - StreamService

@objcMembers
@objc(EZStreamService)
public class StreamService: QueryService {
    // MARK: Lifecycle

    override init() {
        super.init()

        // Since getter Defaults[key] cost CPU high when update too frequently, we observe it here.

        Defaults.publisher(thinkTagKey)
            .removeDuplicates()
            .sink { [weak self] in
                self?.hideThinkTagContent = $0.newValue
            }
            .store(in: &cancellables)
    }

    // MARK: Public

    public override func isStream() -> Bool {
        true
    }

    public override func intelligentQueryTextType() -> EZQueryTextType {
        Configuration.shared.intelligentQueryTextTypeForServiceType(serviceType())
    }

    public override func supportLanguagesDictionary() -> MMOrderedDictionary<AnyObject, AnyObject> {
        let allLanguages = EZLanguageManager.shared().allLanguages
        let supportedLanguages = allLanguages.filter { language in
            !unsupportedLanguages.contains(language)
        }
        return supportedLanguages.toMMOrderedDictionary()
    }

    public override func queryTextType() -> EZQueryTextType {
        var typeOptions: EZQueryTextType = []

        let isTranslationEnabled = Defaults[translationKey].boolValue
        let isSentenceEnabled = Defaults[sentenceKey].boolValue
        let isDictionaryEnabled = Defaults[dictionaryKey].boolValue

        if isTranslationEnabled {
            typeOptions.insert(.translation)
        }
        if isSentenceEnabled {
            typeOptions.insert(.sentence)
        }
        if isDictionaryEnabled {
            typeOptions.insert(.dictionary)
        }

        return typeOptions
    }

    public override func serviceUsageStatus() -> EZServiceUsageStatus {
        let usageStatus = Defaults[serviceUsageStatusKey]
        guard let value = UInt(usageStatus.rawValue) else { return .default }
        return EZServiceUsageStatus(rawValue: value) ?? .default
    }

    public override func configurationListItems() -> Any? {
        StreamConfigurationView(service: self)
    }

    public override func translate(
        _ text: String,
        from: Language,
        to: Language,
        completion: @escaping (EZQueryResult, Error?) -> ()
    ) {
        let queryResultStream = streamTranslate(text: text, from: from, to: to)
        let textStream = queryResultStreamToTextStream(queryResultStream)

        Task {
            do {
                try await throttleUpdateResultText(
                    textStream, queryType: queryTextType(), error: nil
                ) { result in
                    completion(result, result.error)
                }
            } catch {
                completion(result, error)
            }
        }
    }

    // MARK: Internal

    /// A lock for synchronizing access to the 'result' object
    let updateResultLock = NSLock()

    let mustOverride = "This property or method must be overridden by a subclass"

    var cancellables: Set<AnyCancellable> = []

    var hideThinkTagContent: Bool = true

    var model: String {
        get {
            var model = Defaults[modelKey]
            if !validModels.contains(model) || model.isEmpty {
                model = validModels.first ?? ""
                Defaults[modelKey] = model
            }
            return model
        }
        set {
            Defaults[modelKey] = newValue
        }
    }

    var defaultModels: [String] {
        [""]
    }

    var defaultModel: String {
        defaultModels.first ?? ""
    }

    var unsupportedLanguages: [Language] {
        []
    }

    var modelKey: Defaults.Key<String> {
        stringDefaultsKey(.model, defaultValue: defaultModel)
    }

    /// When `supportedModels` is set, `validModels` will be updated automatically.
    var supportedModels: String {
        get { Defaults[supportedModelsKey] }
        set {
            Defaults[supportedModelsKey] = newValue
            Defaults[validModelsKey] = validModels(from: newValue)
        }
    }

    var supportedModelsKey: Defaults.Key<String> {
        stringDefaultsKey(.supportedModels, defaultValue: supportedModels(from: defaultModels))
    }

    var enableCustomPromptKey: Defaults.Key<Bool> {
        boolDefaultsKey(.enableCustomPrompt, defaultValue: false)
    }

    var enableCustomPrompt: Bool {
        get { Defaults[enableCustomPromptKey] }
        set { Defaults[enableCustomPromptKey] = newValue }
    }

    var userPromptKey: Defaults.Key<String> {
        stringDefaultsKey(.userPrompt, defaultValue: "")
    }

    var userPrompt: String {
        get { Defaults[userPromptKey] }
        set { Defaults[userPromptKey] = newValue }
    }

    var systemPromptKey: Defaults.Key<String> {
        stringDefaultsKey(.systemPrompt, defaultValue: "")
    }

    var systemPrompt: String {
        get { Defaults[systemPromptKey] }
        set { Defaults[systemPromptKey] = newValue }
    }

    /// Just getter, we should not change it directly, we should set `supportedModels` instead.
    var validModels: [String] {
        Defaults[validModelsKey]
    }

    var validModelsKey: Defaults.Key<[String]> {
        serviceDefaultsKey(.validModels, defaultValue: defaultModels)
    }

    var apiKey: String {
        Defaults[apiKeyKey]
    }

    var requireAPIKey: Bool {
        true
    }

    var apiKeyKey: Defaults.Key<String> {
        stringDefaultsKey(.apiKey)
    }

    var endpoint: String {
        Defaults[endpointKey].isEmpty ? defaultEndpoint : Defaults[endpointKey]
    }

    var endpointKey: Defaults.Key<String> {
        stringDefaultsKey(.endpoint, defaultValue: defaultEndpoint)
    }

    var endpointPlaceholder: LocalizedStringKey {
        defaultEndpoint
            .isEmpty
            ? "service.configuration.openai.endpoint.placeholder"
            : LocalizedStringKey(defaultEndpoint)
    }

    var defaultEndpoint: String {
        ""
    }

    var nameKey: Defaults.Key<String> {
        stringDefaultsKey(.name)
    }

    var translationKey: Defaults.Key<String> {
        stringDefaultsKey(.translation, defaultValue: "1")
    }

    var sentenceKey: Defaults.Key<String> {
        stringDefaultsKey(.sentence, defaultValue: isSentenceEnabledByDefault ? "1" : "0")
    }

    var isSentenceEnabledByDefault: Bool {
        true
    }

    var dictionaryKey: Defaults.Key<String> {
        stringDefaultsKey(.dictionary, defaultValue: isDictionaryEnabledByDefault ? "1" : "0")
    }

    var isDictionaryEnabledByDefault: Bool {
        true
    }

    var serviceUsageStatusKey: Defaults.Key<ServiceUsageStatus> {
        serviceDefaultsKey(.serviceUsageStatus, defaultValue: .default)
    }

    var thinkTagKey: Defaults.Key<Bool> {
        boolDefaultsKey(.thinkTag, defaultValue: true)
    }

    // In general, LLM services need to observe these keys to enable validation button.
    var observeKeys: [Defaults.Key<String>] {
        [
            apiKeyKey,
            endpointKey,
            supportedModelsKey,
        ]
    }

    var apiKeyPlaceholder: LocalizedStringKey {
        "\(serviceType().rawValue) API Key"
    }

    var temperatureKey: Defaults.Key<Double> {
        serviceDefaultsKey(.temperature, defaultValue: 0.3)
    }

    var temperature: Double {
        Defaults[temperatureKey]
    }

    func validModels(from supportedModels: String) -> [String] {
        supportedModels.components(separatedBy: ",")
            .map { $0.trim() }.filter { !$0.isEmpty }
    }

    func supportedModels(from validModels: [String]) -> String {
        validModels.joined(separator: ", ")
    }

    /// Base on chat query, convert prompt dict to LLM service prompt model.
    func serviceChatMessageModels(_ chatQuery: ChatQueryParam)
        -> [Any] {
        fatalError(mustOverride)
    }

    /// Base on chat query, convert prompt dict to LLM service prompt model.
    /// If enableCustomPrompt is true, we will use custom prompt, otherwise use system prompt.
    func chatMessageDicts(_ chatQuery: ChatQueryParam) -> [ChatMessage] {
        if enableCustomPrompt {
            var chatMessages: [ChatMessage] = []
            let systemPrompt = replaceCustomPromptWithVariable(systemPrompt)
            var userPrompt = replaceCustomPromptWithVariable(userPrompt)

            if !systemPrompt.isEmpty {
                chatMessages.append(.init(role: .system, content: systemPrompt))
            }

            // If user prompt is empty, use query text as user prompt
            if userPrompt.isEmpty {
                userPrompt = queryModel.queryText
            }
            chatMessages.append(.init(role: .user, content: userPrompt))

            return chatMessages
        }
        return builtInChatMessageDicts(chatQuery)
    }

    /// Get query type by text and from && to language.
    func queryType(text: String, from: Language, to: Language) -> EZQueryTextType {
        let enableDictionary = queryTextType().contains(.dictionary)
        var isQueryDictionary = false
        if enableDictionary {
            isQueryDictionary = (text as NSString).shouldQueryDictionary(
                withLanguage: from, maxWordCount: 2
            )
            if isQueryDictionary {
                return .dictionary
            }
        }

        let enableSentence = queryTextType().contains(.sentence)
        var isQueryEnglishSentence = false
        if !isQueryDictionary, enableSentence {
            let isEnglishText = from == .english
            if isEnglishText {
                isQueryEnglishSentence = (text as NSString).shouldQuerySentence(withLanguage: from)
                if isQueryEnglishSentence {
                    return .sentence
                }
            }
        }

        return .translation
    }

    /// Cancel stream request manually.
    func cancelStream() {}

    /// Content stream translate.
    /// Content is the original delta text.
    func contentStreamTranslate(
        _ text: String,
        from: Language,
        to: Language
    )
        -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish(
                throwing: QueryError(
                    type: .api,
                    message:
                    "`\(serviceType().rawValue)` contentStreamTranslate is not implemented"
                )
            )
        }
    }
}
