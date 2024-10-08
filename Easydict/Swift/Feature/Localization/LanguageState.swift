//
//  LanguageState.swift
//  Easydict
//
//  Created by choykarl on 2024/3/3.
//  Copyright © 2024 izual. All rights reserved.
//

import SwiftUI

// MARK: - LanguageState

let languagePreferenceLocalKey = "LanguagePreferenceLocalKey"

// MARK: - LanguageState

class LanguageState: ObservableObject {
    enum LanguageType: String, CaseIterable {
        case english = "en"
        case canadianEnglish = "en-CA"
        case simplifiedChinese = "zh-Hans"
        case traditionalChinese = "zh-Hant"
        case slovak = "sk"

        // MARK: Internal

        var name: String {
            switch self {
            case .english:
                "English"
            case .canadianEnglish:
                "English (Canada)"
            case .simplifiedChinese:
                "简体中文"
            case .traditionalChinese:
                "繁體中文"
            case .slovak:
                "Slovak"
            }
        }
    }

    @AppStorage(languagePreferenceLocalKey) var language: LanguageType = (.init(
        rawValue: I18nHelper.shared.localizeCode
    ) ?? .simplifiedChinese) {
        didSet {
            NotificationCenter.default.post(name: .languagePreferenceChanged, object: nil)
        }
    }
}
