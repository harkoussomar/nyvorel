.pragma library

function han(number) {
    if (number === 100)
        return "一百"
    if (number < 1 || number >= 100)
        return String(number)
    const digits = "〇一二三四五六七八九"
    if (number < 10)
        return digits[number]
    const tens = Math.floor(number / 10)
    const units = number % 10
    return (tens === 1 ? "" : digits[tens]) + "十" + (units ? digits[units] : "")
}

function roman(number) {
    if (number < 1 || number > 3999)
        return String(number)
    const thousands = ["", "M", "MM", "MMM"]
    const hundreds = ["", "C", "CC", "CCC", "CD", "D", "DC", "DCC", "DCCC", "CM"]
    const tens = ["", "X", "XX", "XXX", "XL", "L", "LX", "LXX", "LXXX", "XC"]
    const units = ["", "I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX"]
    return thousands[Math.floor(number / 1000)] + hundreds[Math.floor(number / 100) % 10]
        + tens[Math.floor(number / 10) % 10] + units[number % 10]
}

function style(numberMap) {
    if (!numberMap.length)
        return "decimal"
    // Older configurations stored the same presets with only 20 entries.
    if (numberMap.length === 20 || numberMap.length === 30) {
        if (numberMap.every((label, index) => label === han(index + 1)))
            return "han"
        if (numberMap.every((label, index) => label === roman(index + 1)))
            return "roman"
    }
    return "custom"
}

function preset(numberStyle) {
    if (numberStyle === "han")
        return Array.from({ length: 30 }, (_, index) => han(index + 1))
    if (numberStyle === "roman")
        return Array.from({ length: 30 }, (_, index) => roman(index + 1))
    return []
}

function label(number, numberMap, numberStyle) {
    if (numberStyle === "han")
        return han(number)
    if (numberStyle === "roman")
        return roman(number)
    return numberMap[number - 1] || String(number)
}
