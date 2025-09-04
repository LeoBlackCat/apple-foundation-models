//
//  ArabiziTransliterator.swift
//  FoundationModelsApp
//
//  Created by Leo on 6/16/25.
//

import Foundation

struct ArabiziTransliterator {
    
    /// Transliterates Arabic text to Arabizi (Arabic written in Latin script)
    /// Uses common conventions like 7 for ح, 3 for ع, etc.
    static func transliterate(_ arabicText: String) -> String {
        var result = arabicText
        
        // Arabic to Arabizi mapping
        let transliterationMap: [(String, String)] = [
            // Basic Arabic letters
            ("ا", "a"),
            ("أ", "a"),
            ("إ", "i"),
            ("آ", "aa"),
            ("ب", "b"),
            ("ت", "t"),
            ("ث", "th"),
            ("ج", "j"),
            ("ح", "7"),     // 7 for ح (haa)
            ("خ", "kh"),
            ("د", "d"),
            ("ذ", "th"),
            ("ر", "r"),
            ("ز", "z"),
            ("س", "s"),
            ("ش", "sh"),
            ("ص", "s"),
            ("ض", "d"),
            ("ط", "t"),
            ("ظ", "z"),
            ("ع", "3"),     // 3 for ع (ayn)
            ("غ", "gh"),
            ("ف", "f"),
            ("ق", "q"),
            ("ك", "k"),
            ("ل", "l"),
            ("م", "m"),
            ("ن", "n"),
            ("ه", "h"),
            ("و", "w"),
            ("ي", "y"),
            ("ى", "a"),
            ("ة", "a"),
            ("ء", "'"),
            
            // Vowel marks (tashkeel) - remove them as requested (no diacritics)
            ("َ", ""),      // fatha
            ("ِ", ""),      // kasra
            ("ُ", ""),      // damma
            ("ْ", ""),      // sukun
            ("ّ", ""),      // shadda
            ("ً", ""),      // tanween fath
            ("ٍ", ""),      // tanween kasr
            ("ٌ", ""),      // tanween damm
            ("ٰ", ""),      // alif khanjariyya
            ("ٱ", "a"),     // alif wasla
            
            // Common Arabic words and combinations
            ("لا", "la"),
            ("ال", "al"),
            ("لل", "lil"),
            
            // Numbers (Arabic-Indic to Western)
            ("٠", "0"),
            ("١", "1"),
            ("٢", "2"),
            ("٣", "3"),
            ("٤", "4"),
            ("٥", "5"),
            ("٦", "6"),
            ("٧", "7"),
            ("٨", "8"),
            ("٩", "9"),
            
            // Punctuation
            ("،", ","),
            ("؛", ";"),
            ("؟", "?"),
            ("٪", "%"),
            
            // Special cases for better pronunciation
            ("تش", "ch"),   // ch sound
            ("دج", "j"),    // j sound
            ("كس", "x"),    // x sound
            ("فف", "v"),    // v sound (rare in Arabic)
        ]
        
        // Apply transliterations in order (longer patterns first)
        let sortedMap = transliterationMap.sorted { $0.0.count > $1.0.count }
        
        for (arabic, arabizi) in sortedMap {
            result = result.replacingOccurrences(of: arabic, with: arabizi)
        }
        
        // Clean up multiple spaces and trim
        result = result.replacingOccurrences(of: "  ", with: " ")
        result = result.trimmingCharacters(in: .whitespacesAndNewlines)
        
        return result
    }
    
    /// Processes an AttributedString and transliterates Arabic content to Arabizi
    static func transliterate(_ attributedText: AttributedString) -> AttributedString {
        let arabicText = String(attributedText.characters)
        let transliteratedText = transliterate(arabicText)
        return AttributedString(transliteratedText)
    }
    
    /// Checks if text contains Arabic characters
    static func containsArabic(_ text: String) -> Bool {
        let arabicRange = text.range(of: "[\u{0600}-\u{06FF}\u{0750}-\u{077F}\u{08A0}-\u{08FF}\u{FB50}-\u{FDFF}\u{FE70}-\u{FEFF}]", options: .regularExpression)
        return arabicRange != nil
    }
    
    /// Checks if AttributedString contains Arabic characters
    static func containsArabic(_ attributedText: AttributedString) -> Bool {
        return containsArabic(String(attributedText.characters))
    }
}