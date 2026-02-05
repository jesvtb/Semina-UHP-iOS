//
//  CountryFlag.swift
//  unheardpath
//
//  Maps ISO alpha-2 country codes to flag asset names in Assets.xcassets/iosFlags.
//

import SwiftUI

/// Provides mapping from ISO alpha-2 country codes to flag image assets.
enum CountryFlag {
    
    /// Dictionary mapping ISO alpha-2 codes to asset names in iosFlags folder.
    /// Keys are uppercase ISO codes, values are exact imageset folder names.
    static let assetName: [String: String] = [
        // A
        "AF": "afghanistan",
        "AX": "aland islands",
        "AL": "albania",
        "DZ": "Algeria",
        "AS": "american samoa",
        "AD": "andorra",
        "AO": "angola",
        "AI": "anguilla",
        "AG": "antigua and barbuda",
        "AR": "argentina",
        "AM": "armenia",
        "AW": "aruba",
        "AU": "australia",
        "AT": "austria",
        "AZ": "azerbaijan",
        
        // B
        "BS": "bahamas",
        "BH": "bahrain",
        "BD": "bangladesh",
        "BB": "barbados",
        "BY": "belarus",
        "BE": "belgium",
        "BZ": "belize",
        "BJ": "benin",
        "BM": "bermuda",
        "BT": "bhutan",
        "BO": "bolivia",
        "BQ": "bonaire",
        "BA": "bosnia and herzegovina",
        "BW": "botswana",
        "BR": "brazil",
        "IO": "british indian ocean territory",
        "VG": "british virgin islands",
        "BN": "brunei",
        "BG": "bulgaria",
        "BF": "burkina faso",
        "BI": "burundi",
        
        // C
        "KH": "cambodia",
        "CM": "cameroon",
        "CA": "canada",
        "CV": "cape verde",
        "KY": "cayman islands",
        "CF": "central african republic",
        "TD": "chad",
        "CL": "chile",
        "CN": "china",
        "CC": "cocos island",
        "CO": "colombia",
        "KM": "comoros",
        "CG": "republic of the congo",
        "CD": "democratic republic of congo",
        "CK": "cook islands",
        "CR": "costa rica",
        "HR": "croatia",
        "CU": "cuba",
        "CW": "curacao",
        "CY": "cyprus",
        "CZ": "czech republic",
        
        // D
        "DK": "denmark",
        "DJ": "djibouti",
        "DM": "dominica",
        "DO": "dominican republic",
        
        // E
        "EC": "ecuador",
        "EG": "egypt",
        "SV": "el salvador",
        "GQ": "equatorial guinea",
        "ER": "eritrea",
        "EE": "estonia",
        "SZ": "swaziland",
        "ET": "ethiopia",
        
        // F
        "FK": "falkland islands",
        "FO": "faroe islands",
        "FJ": "fiji",
        "FI": "finland",
        "FR": "france",
        "PF": "french polynesia",
        
        // G
        "GA": "gabon",
        "GM": "gambia",
        "GE": "georgia",
        "DE": "germany",
        "GH": "ghana",
        "GI": "gibraltar",
        "GR": "greece",
        "GL": "greenland",
        "GD": "grenada",
        "GU": "guam",
        "GT": "guatemala",
        "GG": "guernsey",
        "GN": "guinea",
        "GW": "guinea bissau",
        "GY": "guyana",
        
        // H
        "HT": "haiti",
        "HN": "honduras",
        "HK": "hong kong",
        "HU": "hungary",
        
        // I
        "IS": "iceland",
        "IN": "india",
        "ID": "indonesia",
        "IR": "iran",
        "IQ": "iraq",
        "IE": "ireland",
        "IM": "isle of man",
        "IL": "israel",
        "IT": "italy",
        "CI": "ivory coast",
        
        // J
        "JM": "jamaica",
        "JP": "japan",
        "JE": "jersey",
        "JO": "jordan",
        
        // K
        "KZ": "kazakhstan",
        "KE": "kenya",
        "KI": "kiribati",
        "XK": "kosovo",
        "KW": "kuwait",
        "KG": "kyrgyzstan",
        
        // L
        "LA": "laos",
        "LV": "latvia",
        "LB": "lebanon",
        "LS": "lesotho",
        "LR": "liberia",
        "LY": "libya",
        "LI": "liechtenstein",
        "LT": "lithuania",
        "LU": "luxembourg",
        
        // M
        "MO": "macao",
        "MG": "madagascar",
        "MW": "malawi",
        "MY": "malaysia",
        "MV": "maldives",
        "ML": "mali",
        "MT": "malta",
        "MH": "marshall island",
        "MQ": "martinique",
        "MR": "mauritania",
        "MU": "mauritius",
        "MX": "mexico",
        "FM": "micronesia",
        "MD": "moldova",
        "MC": "monaco",
        "MN": "mongolia",
        "ME": "montenegro",
        "MS": "montserrat",
        "MA": "morocco",
        "MZ": "mozambique",
        "MM": "myanmar",
        
        // N
        "NA": "namibia",
        "NR": "nauru",
        "NP": "nepal",
        "NL": "netherlands",
        "NZ": "new zealand",
        "NI": "nicaragua",
        "NE": "niger",
        "NG": "nigeria",
        "NU": "niue",
        "NF": "norfolk island",
        "KP": "north korea",
        "MK": "republic of macedonia",
        "MP": "northern marianas islands",
        "NO": "norway",
        
        // O
        "OM": "oman",
        
        // P
        "PK": "pakistan",
        "PW": "palau",
        "PS": "palestine",
        "PA": "panama",
        "PG": "papua new guinea",
        "PY": "paraguay",
        "PE": "peru",
        "PH": "philippines",
        "PN": "pitcairn islands",
        "PL": "poland",
        "PT": "portugal",
        "PR": "puerto rico",
        
        // Q
        "QA": "qatar",
        
        // R
        "RO": "romania",
        "RU": "russia",
        "RW": "rwanda",
        
        // S
        "BL": "st barts",
        "LC": "st lucia",
        "VC": "st vincent and the grenadines",
        "WS": "samoa",
        "SM": "san marino",
        "ST": "sao tome and prince",
        "SA": "saudi arabia",
        "SN": "senegal",
        "RS": "serbia",
        "SC": "seychelles",
        "SL": "sierra leone",
        "SG": "singapore",
        "SX": "sint maarten",
        "SK": "slovakia",
        "SI": "slovenia",
        "SB": "solomon islands",
        "SO": "somalia",
        "ZA": "south africa",
        "KR": "south korea",
        "SS": "south sudan",
        "ES": "spain",
        "LK": "sri lanka",
        "SD": "sudan",
        "SR": "suriname",
        "SE": "sweden",
        "CH": "switzerland",
        "SY": "syria",
        
        // T
        "TW": "taiwan",
        "TJ": "tajikistan",
        "TZ": "tanzania",
        "TH": "thailand",
        "TL": "East Timor",
        "TG": "togo",
        "TK": "tokelau",
        "TO": "tonga",
        "TT": "trinidad and tobago",
        "TN": "tunisia",
        "TR": "turkey",
        "TM": "turkmenistan",
        "TC": "turks and caicos",
        "TV": "tuvalu",
        
        // U
        "UG": "uganda",
        "UA": "ukraine",
        "AE": "united arab emirates",
        "GB": "united kingdom",
        "US": "united states",
        "VI": "virgin islands",
        "UY": "uruguay",
        "UZ": "uzbekistán",
        
        // V
        "VU": "vanuatu",
        "VA": "vatican city",
        "VE": "venezuela",
        "VN": "vietnam",
        
        // W
        // (Wales, England, Scotland are not ISO countries but included as regions)
        
        // Y
        "YE": "yemen",
        
        // Z
        "ZM": "zambia",
        "ZW": "zimbabwe",
    ]
    
    /// Regional/special flags that don't have standard ISO alpha-2 codes.
    /// Use these identifiers directly with `flagImage(for:)`.
    static let regionalAssets: [String: String] = [
        "ABKHAZIA": "abkhazia",
        "AZORES": "azores islands",
        "BALEARIC": "balearic islands",
        "BASQUE": "basque country",
        "BRITISH_COLUMBIA": "british columbia",
        "CANARY": "canary islands",
        "CEUTA": "ceuta",
        "CORSICA": "corsica",
        "ENGLAND": "england",
        "EU": "european union",
        "GALAPAGOS": "galapagos islands",
        "HAWAII": "hawaii",
        "MADEIRA": "madeira",
        "MELILLA": "melilla",
        "NATO": "nato",
        "NORTHERN_CYPRUS": "northern cyprus",
        "ORKNEY": "orkney islands",
        "OSSETIA": "ossetia",
        "RAPA_NUI": "Rapa Nui",
        "SABA": "saba island",
        "SAHRAWI": "sahrawi arab democratic republic",
        "SARDINIA": "sardinia",
        "SCOTLAND": "scotland",
        "SINT_EUSTATIUS": "sint eustatius",
        "SOMALILAND": "somaliland",
        "TIBET": "tibet",
        "TRANSNISTRIA": "transnistria",
        "UN": "united nations",
        "WALES": "wales",
    ]
    
    /// Returns a flag Image for the given ISO alpha-2 country code.
    /// - Parameter code: ISO alpha-2 country code (e.g., "US", "GB", "FR"). Case-insensitive.
    /// - Returns: Image view if the flag asset exists, nil otherwise.
    static func image(for code: String) -> Image? {
        let uppercased = code.uppercased()
        
        // Check standard ISO codes first
        if let assetName = assetName[uppercased] {
            return Image(assetName)
        }
        
        // Check regional/special codes
        if let assetName = regionalAssets[uppercased] {
            return Image(assetName)
        }
        
        return nil
    }
    
    /// Returns the asset name for the given ISO alpha-2 country code.
    /// Useful for debugging or when you need the raw asset name.
    /// - Parameter code: ISO alpha-2 country code. Case-insensitive.
    /// - Returns: Asset name string if found, nil otherwise.
    static func assetNameFor(code: String) -> String? {
        let uppercased = code.uppercased()
        return assetName[uppercased] ?? regionalAssets[uppercased]
    }
}
