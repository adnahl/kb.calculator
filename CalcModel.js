.pragma library

// Arithmetic evaluator for the calculator overlay.
//
// Grammar (precedence climbing, no eval()):
//
//   expression  := additive
//   additive    := multiplicative (('+' | '-') multiplicative)*
//   multiplicative := unary (('*' | '/' | '%') unary | implicit-mul unary)*
//   unary       := ('+' | '-') unary | power
//   power       := primary ('^' unary)?          right-associative, binds tighter than unary minus
//   primary     := number | '(' expression ')' | '√' unary | name
//
// Accepted input sugar: a number followed by '(' , a name or '√' multiplies
// (2(3+4), 2pi), '*' may be typed as x/X, and '**' is the same as '^'.
// Locale habits are normalised: ' as a thousands separator (1'000), a decimal
// comma (0,5), and the typographic × ÷ − − π √ characters.

let FUNCTIONS = {
	sqrt: { min: 1, max: 1, apply: function (a) { return Math.sqrt(a) } },
	abs: { min: 1, max: 1, apply: function (a) { return Math.abs(a) } },
	round: { min: 1, max: 2, apply: function (a) { return roundTo(a[0], a.length > 1 ? a[1] : 0) } },
	floor: { min: 1, max: 1, apply: function (a) { return Math.floor(a[0]) } },
	ceil: { min: 1, max: 1, apply: function (a) { return Math.ceil(a[0]) } }
}

const CONSTANTS = {
	pi: Math.PI,
	"\u03c0": Math.PI, // π
	e: Math.E,
	"\u212f": Math.E, // ℯ
}

// Route through the exponent string: 1.005 * 100 lands on 100.49999… in binary,
// which would make round(x, 2) return 1 instead of 1.01.
function roundTo(value, digits) {
	if (digits !== Math.floor(digits) || digits < 0 || digits > 15) return NaN
	let sign = value < 0 ? -1 : 1
	return sign * Number(Math.round(Number(Math.abs(value) + "e" + digits)) + "e-" + digits)
}

function normalize(expression) {
	return String(expression || "")
		.replace(/=\s*$/, "")
		.replace(/\u00d7/g, "*")
		.replace(/\u00f7/g, "/")
		.replace(/\u2212/g, "-")
		.replace(/([\d)]\s*)[xX](?=\s*[\d(.])/g, "$1*")
		.replace(/(\d)'(?=\d)/g, "$1")
		.replace(/(\d),(?=\d)/g, "$1.")
		.trim()
}

// What the field shows: * becomes × and - becomes −. ** is rewritten to ^ first,
// which is the one substitution that changes the length, so the cursor is
// mapped through the same pass.
function prettify(text, cursor) {
	let value = String(text || "")
	return {
		text: prettyPass(value),
		cursor: prettyPass(value.slice(0, cursor)).length
	}
}

function prettyPass(value) {
	return value
		.replace(/\*\*/g, "^")
		.replace(/\*/g, "\u00d7")
		.replace(/-/g, "\u2212")
		.replace(/([\d)]\s*)[xX](?=\s*[\d(.])/g, "$1\u00d7")
}

function tokenize(text) {
	let tokens = []
	let i = 0
	while (i < text.length) {
		let rest = text.slice(i)
		let ch = text[i]

		if (/\s/.test(ch)) { i++; continue }

		let number = /^(\d+\.?\d*|\.\d+)/.exec(rest)
		if (number) {
			tokens.push({ type: "num", value: parseFloat(number[0]) })
			i += number[0].length
			continue
		}

		let name = /^(?:[a-zA-Z]+|\u03c0)/.exec(rest)
		if (name) {
			tokens.push({ type: "name", value: name[0].toLowerCase() })
			i += name[0].length
			continue
		}

		if (rest.indexOf("**") === 0) { tokens.push({ type: "^" }); i += 2; continue }
		if ("+-*/%^()\u221a;,".indexOf(ch) >= 0) {
			tokens.push({ type: ch === "," ? ";" : ch })
			i++
			continue
		}

		return null
	}
	return tokens
}

function parse(tokens) {
	let pos = 0

	function peek(offset) { return tokens[pos + (offset || 0)] }
	function take() { return tokens[pos++] }
	function fail() { throw new Error("invalid") }
	function is(token, type) { return !!token && token.type === type }
	function accept(type) { if (is(peek(), type)) { pos++; return true } return false }
	function startsOperand(token) {
		return !!token && (is(token, "num") || is(token, "(") || is(token, "name") || is(token, "\u221a"))
	}
	// A factor that may follow another operand without an operator between them.
	// Deliberately excludes numbers: "2 3" is a typo, not a product.
	function startsFactor(token) {
		return !!token && (is(token, "(") || is(token, "name") || is(token, "\u221a"))
	}

	// Operands carry { value, percent }. percent is the raw number behind a
	// trailing b%, kept so that "80 + 10%" can apply 10% of 80 rather than 0.1.
	function expression() {
		let left = multiplicative()
		while (is(peek(), "+") || is(peek(), "-")) {
			let op = take().type
			let right = multiplicative()
			let amount = right.percent === null ? right.value : left.value * right.percent / 100
			left = { value: op === "+" ? left.value + amount : left.value - amount, percent: null }
		}
		return left
	}

	function multiplicative() {
		let left = unary()
		while (true) {
			let token = peek()
			let op
			if (is(token, "*") || is(token, "/")) {
				op = take().type
			} else if (is(token, "%")) {
				// postfix() already ate a trailing "%", so reaching here means modulo.
				take()
				op = "%"
			} else if (startsFactor(token)) {
				op = "*"
			} else {
				break
			}

			let right = unary()
			let value
			if (op === "*") value = left.value * right.value
			else if (op === "/") value = left.value / right.value
			else value = left.value % right.value
			left = { value: value, percent: null }
		}
		return left
	}

	function unary() {
		if (is(peek(), "+") || is(peek(), "-")) {
			let op = take().type
			let inner = unary()
			return op === "-" ? { value: -inner.value, percent: null } : inner
		}
		return power()
	}

	function power() {
		let base = postfix()
		if (accept("^")) return { value: Math.pow(base.value, unary().value), percent: null }
		return base
	}

	function postfix() {
		let base = primary()
		// A trailing "%" divides by 100; a "%" with an operand after it is modulo,
		// which multiplicative() handles.
		if (is(peek(), "%") && !startsOperand(peek(1))) {
			pos++
			return { value: base.value / 100, percent: base.value }
		}
		return { value: base.value, percent: null }
	}

	function primary() {
		let token = take()
		if (!token) fail()
		if (is(token, "num")) return { value: token.value, percent: null }
		if (is(token, "\u221a")) return { value: Math.sqrt(unary().value), percent: null }
		if (is(token, "(")) {
			let inner = expression()
			if (!is(take(), ")")) fail()
			return { value: inner.value, percent: null }
		}
		if (is(token, "name")) {
			if (CONSTANTS.hasOwnProperty(token.value)) return { value: CONSTANTS[token.value], percent: null }
			let fn = FUNCTIONS.hasOwnProperty(token.value) ? FUNCTIONS[token.value] : null
			if (!fn || !is(take(), "(")) fail()
			let args = [expression().value]
			while (accept(";")) args.push(expression().value)
			if (!is(take(), ")")) fail()
			if (args.length < fn.min || args.length > fn.max) fail()
			return { value: fn.apply(args), percent: null }
		}
		fail()
	}

	let result = expression()
	if (pos !== tokens.length) fail()
	return result.value
}

function format(value) {
	if (!isFinite(value)) return null
	let rounded = parseFloat(value.toPrecision(15))
	if (rounded === 0) rounded = 0
	let text = String(rounded)
	// 1e21 prints as "1e+21", which nobody wants to read; spell it out while it
	// still fits a sensible number of digits.
	if (/e/.test(text) && Math.abs(rounded) >= 1 && Math.abs(rounded) < 1e21) text = rounded.toFixed(0)
	return text
}

// Result as a plain string, or null when the input is not a complete
// calculation. A lone number is not a calculation, so it gets no result.
function evaluate(expression) {
	let text = normalize(expression)
	if (!text || /^[+-]?(?:\d+\.?\d*|\.\d+)$/.test(text)) return null
	let tokens = tokenize(text)
	if (!tokens || tokens.length === 0) return null
	try {
		return format(parse(tokens))
	} catch (e) {
		return null
	}
}

// Accumulate in the output base instead of using Number, which rounds large
// integers. Each intermediate value is at most 16 * 16.
function convertDigits(text, fromBase, toBase) {
	let digits = [0]
	for (let i = 0; i < text.length; i++) {
		let carry = parseInt(text[i], fromBase)
		for (let j = 0; j < digits.length; j++) {
			let value = digits[j] * fromBase + carry
			digits[j] = value % toBase
			carry = Math.floor(value / toBase)
		}
		while (carry > 0) {
			digits.push(carry % toBase)
			carry = Math.floor(carry / toBase)
		}
	}
	return digits.reverse().map(function (digit) { return digit.toString(toBase).toUpperCase() }).join("")
}

function convertInteger(input, base) {
	let empty = { decimal: "", hexadecimal: "", binary: "", error: "" }
	if (base !== 2 && base !== 10 && base !== 16) {
		empty.error = "Choose binary, decimal, or hexadecimal."
		return empty
	}
	let text = String(input || "").trim()
	if (!text) return empty
	let negative = text[0] === "-"
	if (text[0] === "-" || text[0] === "+") text = text.slice(1)
	if (base === 16) text = text.replace(/^0x/i, "")
	if (base === 2) text = text.replace(/^0b/i, "")
	let pattern = base === 16 ? /^[0-9a-f]+$/i : base === 2 ? /^[01]+$/ : /^[0-9]+$/
	if (!pattern.test(text)) {
		empty.error = base === 16 ? "Use hexadecimal digits 0-9 and A-F (optional 0x prefix)."
			: base === 2 ? "Use binary digits 0 and 1 (optional 0b prefix)."
				: "Use decimal digits 0-9. Only integers are supported."
		return empty
	}
	text = text.replace(/^0+(?=.)/, "")
	let sign = negative && text !== "0" ? "-" : ""
	return {
		decimal: sign + convertDigits(text, base, 10),
		hexadecimal: sign + convertDigits(text, base, 16),
		binary: sign + convertDigits(text, base, 2),
		error: ""
	}
}

const UNIT_CATEGORIES = [
	{
		id: "length",
		label: "Length",
		units: [
			{ id: "mm", name: "Millimeters (mm)", symbol: "mm", factor: 0.001 },
			{ id: "cm", name: "Centimeters (cm)", symbol: "cm", factor: 0.01 },
			{ id: "m", name: "Meters (m)", symbol: "m", factor: 1 },
			{ id: "km", name: "Kilometers (km)", symbol: "km", factor: 1000 },
			{ id: "in", name: "Inches (in)", symbol: "in", factor: 0.0254 },
			{ id: "ft", name: "Feet (ft)", symbol: "ft", factor: 0.3048 },
			{ id: "yd", name: "Yards (yd)", symbol: "yd", factor: 0.9144 },
			{ id: "mi", name: "Miles (mi)", symbol: "mi", factor: 1609.344 },
		],
	},
	{
		id: "area",
		label: "Area",
		units: [
			{ id: "mm2", name: "Square millimeters (mm²)", symbol: "mm²", factor: 0.000001 },
			{ id: "cm2", name: "Square centimeters (cm²)", symbol: "cm²", factor: 0.0001 },
			{ id: "m2", name: "Square meters (m²)", symbol: "m²", factor: 1 },
			{ id: "km2", name: "Square kilometers (km²)", symbol: "km²", factor: 1000000 },
			{ id: "in2", name: "Square inches (in²)", symbol: "in²", factor: 0.00064516 },
			{ id: "ft2", name: "Square feet (ft²)", symbol: "ft²", factor: 0.09290304 },
			{ id: "yd2", name: "Square yards (yd²)", symbol: "yd²", factor: 0.83612736 },
			{ id: "acre", name: "Acres", symbol: "ac", factor: 4046.8564224 },
			{ id: "ha", name: "Hectares (ha)", symbol: "ha", factor: 10000 },
		],
	},
	{
		id: "volume",
		label: "Volume",
		units: [
			{ id: "ml", name: "Milliliters (mL)", symbol: "mL", factor: 0.000001 },
			{ id: "l", name: "Liters (L)", symbol: "L", factor: 0.001 },
			{ id: "m3", name: "Cubic meters (m³)", symbol: "m³", factor: 1 },
			{ id: "tsp", name: "US teaspoons (tsp)", symbol: "tsp", factor: 0.00000492892159375 },
			{ id: "tbsp", name: "US tablespoons (tbsp)", symbol: "tbsp", factor: 0.00001478676478125 },
			{ id: "floz", name: "US fluid ounces (fl oz)", symbol: "fl oz", factor: 0.0000295735295625 },
			{ id: "cup", name: "US cups", symbol: "cups", factor: 0.0002365882365 },
			{ id: "pt", name: "US pints (pt)", symbol: "pt", factor: 0.000473176473 },
			{ id: "qt", name: "US quarts (qt)", symbol: "qt", factor: 0.000946352946 },
			{ id: "gal", name: "US gallons (gal)", symbol: "gal", factor: 0.003785411784 },
		],
	},
	{
		id: "temperature",
		label: "Temperature",
		units: [
			{ id: "c", name: "Celsius (°C)", symbol: "°C" },
			{ id: "f", name: "Fahrenheit (°F)", symbol: "°F" },
			{ id: "k", name: "Kelvin (K)", symbol: "K" },
		],
	},
	{
		id: "mass",
		label: "Mass",
		units: [
			{ id: "mg", name: "Milligrams (mg)", symbol: "mg", factor: 0.000001 },
			{ id: "g", name: "Grams (g)", symbol: "g", factor: 0.001 },
			{ id: "kg", name: "Kilograms (kg)", symbol: "kg", factor: 1 },
			{ id: "tonne", name: "Metric tonnes (t)", symbol: "t", factor: 1000 },
			{ id: "oz", name: "Ounces (oz)", symbol: "oz", factor: 0.028349523125 },
			{ id: "lb", name: "Pounds (lb)", symbol: "lb", factor: 0.45359237 },
			{ id: "ton", name: "US short tons", symbol: "ton", factor: 907.18474 },
		],
	},
]

function unitCategories() {
	return UNIT_CATEGORIES.map(function (category) {
		return { id: category.id, label: category.label }
	})
}

function unitsForCategory(categoryId) {
	let category = UNIT_CATEGORIES.find(function (item) { return item.id === categoryId })
	return category ? category.units : []
}

function unitCategoryLabel(categoryId) {
	let category = UNIT_CATEGORIES.find(function (item) { return item.id === categoryId })
	return category ? category.label : "Units"
}

function unitName(categoryId, unitId) {
	let unit = unitsForCategory(categoryId).find(function (item) { return item.id === unitId })
	return unit ? unit.name : ""
}

function unitSymbol(categoryId, unitId) {
	let unit = unitsForCategory(categoryId).find(function (item) { return item.id === unitId })
	return unit ? unit.symbol : ""
}

function convertUnit(input, categoryId, fromId, toId) {
	let empty = { value: "", error: "" }
	let text = (input === null || typeof input === "undefined" ? "" : String(input)).trim().replace(",", ".")
	if (!text) return empty
	if (!/^[+-]?(?:\d+(?:\.\d*)?|\.\d+)$/.test(text)) {
		empty.error = "Enter a number. Use a decimal point or comma; expressions are not supported."
		return empty
	}
	let value = Number(text)
	if (!isFinite(value)) {
		empty.error = "Enter a finite number."
		return empty
	}
	let category = UNIT_CATEGORIES.find(function (item) { return item.id === categoryId })
	let from = category && category.units.find(function (item) { return item.id === fromId })
	let to = category && category.units.find(function (item) { return item.id === toId })
	if (!from || !to) {
		empty.error = "Choose valid units."
		return empty
	}

	let converted
	if (categoryId === "temperature") {
		let celsius = fromId === "c" ? value : fromId === "f" ? (value - 32) * 5 / 9 : value - 273.15
		if (celsius < -273.15 - 1e-10) {
			empty.error = "Temperature cannot be below absolute zero (0 K)."
			return empty
		}
		if (celsius < -273.15) celsius = -273.15
		converted = toId === "c" ? celsius : toId === "f" ? celsius * 9 / 5 + 32 : celsius + 273.15
	} else {
		converted = value * from.factor / to.factor
	}
	if (!isFinite(converted)) {
		empty.error = "The converted value is out of range."
		return empty
	}
	if (Math.abs(converted) < 1e-14) converted = 0
	return { value: format(converted), error: "" }
}

function parseDate(input) {
	let text = String(input || "").trim()
	let match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(text)
	if (!match) return null
	let year = Number(match[1])
	let month = Number(match[2])
	let day = Number(match[3])
	if (year < 1 || month < 1 || month > 12 || day < 1 || day > 31) return null
	let date = new Date(0)
	date.setUTCHours(0, 0, 0, 0)
	date.setUTCFullYear(year, month - 1, day)
	if (date.getUTCFullYear() !== year || date.getUTCMonth() !== month - 1 || date.getUTCDate() !== day) return null
	return date
}

function formatDate(date) {
	let year = ("0000" + date.getUTCFullYear()).slice(-4)
	let month = ("00" + (date.getUTCMonth() + 1)).slice(-2)
	let day = ("00" + date.getUTCDate()).slice(-2)
	return year + "-" + month + "-" + day
}

function calculateDate(mode, firstInput, secondInput) {
	let empty = { value: "", error: "", copy: "", detail: "" }
	let firstText = String(firstInput || "").trim()
	if (!firstText) return empty
	let first = parseDate(firstText)
	if (!first) {
		empty.error = "Enter a valid date in YYYY-MM-DD format."
		return empty
	}

	if (mode === "between") {
		let secondText = String(secondInput || "").trim()
		if (!secondText) return empty
		let second = parseDate(secondText)
		if (!second) {
			empty.error = "Enter a valid end date in YYYY-MM-DD format."
			return empty
		}
		let days = Math.abs((second.getTime() - first.getTime()) / 86400000)
		let label = days === 1 ? "day" : "days"
		let value = String(days) + " " + label
		return {
			value: value,
			error: "",
			copy: value,
			detail: firstText + " to " + secondText + ": " + value,
		}
	}

	if (mode !== "add") {
		empty.error = "Choose a valid date calculation."
		return empty
	}
	let offsetText = secondInput === null || typeof secondInput === "undefined" ? "" : String(secondInput).trim()
	if (!offsetText) return empty
	if (!/^[+-]?\d+$/.test(offsetText)) {
		empty.error = "Enter a whole number of days, such as 7 or -3."
		return empty
	}
	let offset = Number(offsetText)
	if (!isFinite(offset) || Math.floor(offset) !== offset || Math.abs(offset) > 9007199254740991) {
		empty.error = "The number of days is out of range."
		return empty
	}
	let result = new Date(first.getTime() + offset * 86400000)
	if (!isFinite(result.getTime()) || result.getUTCFullYear() < 1 || result.getUTCFullYear() > 9999) {
		empty.error = "The resulting date must be between 0001-01-01 and 9999-12-31."
		return empty
	}
	let resultText = formatDate(result)
	let sign = offset < 0 ? " - " + Math.abs(offset) : " + " + offset
	let dayLabel = Math.abs(offset) === 1 ? "day" : "days"
	return {
		value: resultText,
		error: "",
		copy: resultText,
		detail: firstText + sign + " " + dayLabel + " = " + resultText,
	}
}

function matchingParen(text, index) {
	let ch = text[index]
	if (ch !== "(" && ch !== ")") return -1
	let step = ch === "(" ? 1 : -1
	let depth = 0
	for (let i = index; i >= 0 && i < text.length; i += step) {
		if (text[i] === "(") depth += step
		else if (text[i] === ")") depth -= step
		if (depth === 0) return i
	}
	return -1
}

// Deleting a parenthesis takes its partner with it, so backspacing after
// "(1+2" does not leave a stray ")". Returns { text, cursor }, or null.
function deleteParenPair(text, index) {
	let partner = matchingParen(text, index)
	if (partner < 0) return null
	let first = Math.min(index, partner)
	let second = Math.max(index, partner)
	return {
		text: text.slice(0, first) + text.slice(first + 1, second) + text.slice(second + 1),
		cursor: index < partner ? index : index - 1
	}
}