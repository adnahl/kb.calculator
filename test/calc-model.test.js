#!/usr/bin/env node
"use strict";

// Tests for CalcModel.js without a QML host: node test/calc-model.test.js
// CalcModel.js is a QML `.pragma library` module; stripping that line lets node
// run it as the same plain-JS module it is under QML.

const fs = require("fs");
const path = require("path");
const vm = require("vm");

const source = fs
	.readFileSync(path.join(__dirname, "..", "CalcModel.js"), "utf8")
	.replace(/^\.pragma library\s*/, "");
const model = {};
vm.createContext(model);
vm.runInContext(source, model, { filename: "CalcModel.js" });

let checks = 0;
let failures = 0;

function check(label, actual, expected) {
	checks++;
	const same = JSON.stringify(actual) === JSON.stringify(expected);
	if (!same) {
		failures++;
		console.error(
			`FAIL ${label}: expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`,
		);
	}
}

const evaluations = [
	// Precedence and grouping
	["1 + 2 * 3", "7"],
	["(1 + 2) * 3", "9"],
	["2 + 3 * 4 - 6 / 2", "11"],
	["6 * 7", "42"],
	["72 / 8", "9"],
	["100 / 8", "12.5"],

	// Powers, right-associative and tighter than unary minus
	["2 ^ 3 ^ 2", "512"],
	["-2 ^ 2", "-4"],
	["2 ^ -2", "0.25"],
	["9 ** 2", "81"],

	// Unary signs
	["-5", null],
	["- 5 + 3", "-2"],
	["+4 + 1", "5"],
	["- -3", "3"],

	// Implicit multiplication
	["2(3 + 4)", "14"],
	["2pi", "6.28318530717959"],
	["(1 + 1)(2 + 2)", "8"],
	["2√9", "6"],

	// Percent: trailing divides by 100, with an operand it is modulo
	["50%", "0.5"],
	["200 * 15%", "30"],
	["80 + 10%", "88"],
	["80 - 25%", "60"],
	["17 % 5", "2"],

	// Functions and constants
	["sqrt(16)", "4"],
	["√25", "5"],
	["abs(0 - 7)", "7"],
	["round(3.14159, 2)", "3.14"],
	["round(2.5)", "3"],
	["round(0 - 2.5)", "-3"],
	["round(1.005, 2)", "1.01"],
	["floor(2.9)", "2"],
	["ceil(2.1)", "3"],
	["pi", "3.14159265358979"],
	["π", "3.14159265358979"],
	["e", "2.71828182845905"],
	["round(1; 2) + 1", "2"],

	// Typed sugar
	["2 x 3", "6"],
	["5 X 4", "20"],
	["6 \u00d7 7", "42"],
	["72 \u00f7 8", "9"],
	["\u2212 3 + 5", "2"],
	["1'000 + 1", "1001"],
	["0,5 + 0,25", "0.75"],
	["1 2", null],
	["2 3 4", null],

	// A lone number is not a calculation
	["42", null],
	["3.14", null],
	["", null],
	["   ", null],
	["0", null],

	// Incomplete or invalid input yields no result rather than a wrong one
	["1 +", null],
	["(1 + 2", null],
	["1 + 2)", null],
	["1 + 2 3", null],
	["1 / 0", null],
	["nope(2)", null],
	["sqrt(1, 2)", null],
	["1 + 2 =", "3"],
	["12 / 4 =", "3"],
	["--", null],
	["$5", null],
].forEach(([input, expected]) =>
	check(`evaluate(${JSON.stringify(input)})`, model.evaluate(input), expected),
);

// prettify() rewrites what the field shows and keeps the cursor on the same
// character. Cursor position is checked mid-string, since that is where a
// rewrite shifts text under the caret.
const prettified = [
	["2 * 3", 5, { text: "2 \u00d7 3", cursor: 5 }],
	["2 ** 3", 5, { text: "2 ^ 3", cursor: 4 }],
	["3 ** 2", 2, { text: "3 ^ 2", cursor: 2 }],
	["3 ** 2", 1, { text: "3 ^ 2", cursor: 1 }],
	["10 - 4", 4, { text: "10 \u2212 4", cursor: 4 }],
	["10 - 4", 2, { text: "10 \u2212 4", cursor: 2 }],
	["2 x 3", 3, { text: "2 \u00d7 3", cursor: 3 }],
	["3 ** 2 * 4", 11, { text: "3 ^ 2 \u00d7 4", cursor: 9 }],
	["", 0, { text: "", cursor: 0 }],
].map(([input, cursor, expected]) => [
	`prettify(${JSON.stringify(input)}, ${cursor})`,
	model.prettify(input, cursor),
	expected,
]);

prettified.forEach(([label, actual, expected]) =>
	check(label, actual, expected),
);

const deleted = [
	// Deleting either end takes the whole pair: "(1+2)" loses both parens.
	["(1+2)", 0, { text: "1+2", cursor: 0 }],
	["(1+2)", 4, { text: "1+2", cursor: 3 }],
	["(1+2)", 2, null],
	// Unmatched or absent parens: nothing special happens.
	["(1+2", 0, null],
	["1+2)", 3, null],
	["()", 0, { text: "", cursor: 0 }],
	["a(b(c))d", 1, { text: "ab(c)d", cursor: 1 }],
	["1+2", 1, null],
].map(([text, index, expected]) => [
	`deleteParenPair(${JSON.stringify(text)}, ${index})`,
	model.deleteParenPair(text, index),
	expected,
]);

deleted.forEach(([label, actual, expected]) => check(label, actual, expected));

const conversions = [
	["255", 10, "255", "FF", "11111111"],
	["0xff", 16, "255", "FF", "11111111"],
	["0Xff", 16, "255", "FF", "11111111"],
	["FF", 16, "255", "FF", "11111111"],
	["0b101010", 2, "42", "2A", "101010"],
	["0B101010", 2, "42", "2A", "101010"],
	["101010", 2, "42", "2A", "101010"],
	["1010", 10, "1010", "3F2", "1111110010"],
	["1010", 16, "4112", "1010", "1000000010000"],
	["-0xFF", 16, "-255", "-FF", "-11111111"],
	["-101010", 2, "-42", "-2A", "-101010"],
	["-42", 10, "-42", "-2A", "-101010"],
	[" +00042 ", 10, "42", "2A", "101010"],
	["000f", 16, "15", "F", "1111"],
	["0001", 2, "1", "1", "1"],
	["0", 10, "0", "0", "0"],
	["-000", 2, "0", "0", "0"],
	["-0x00", 16, "0", "0", "0"],
	[
		"9007199254740993",
		10,
		"9007199254740993",
		"20000000000001",
		"100000000000000000000000000000000000000000000000000001",
	],
	[
		"FFFFFFFFFFFFFFFF",
		16,
		"18446744073709551615",
		"FFFFFFFFFFFFFFFF",
		"1".repeat(64),
	],
];
conversions.forEach(([input, base, decimal, hexadecimal, binary]) => {
	check(
		`convertInteger(${JSON.stringify(input)}, ${base})`,
		model.convertInteger(input, base),
		{ decimal, hexadecimal, binary, error: "" },
	);
});

for (const base of [2, 10, 16]) {
	for (const input of ["", "   "]) {
		check(`empty input in base ${base}`, model.convertInteger(input, base), {
			decimal: "",
			hexadecimal: "",
			binary: "",
			error: "",
		});
	}
}

for (const [input, base] of [
	["2", 2],
	["102", 2],
	["0xFF", 2],
	["0b", 2],
	["G", 16],
	["0x", 16],
	["0xFG", 16],
	["1.5", 16],
	["1.5", 10],
	["1e3", 10],
	["0x10", 10],
	["0b10", 10],
	["1 000", 10],
	["1'000", 10],
	["1,000", 10],
	["1+2", 10],
	["-", 10],
	["+", 16],
	["--1", 2],
	["- 1", 10],
	["42", 8],
]) {
	const result = model.convertInteger(input, base);
	check(
		`invalid ${JSON.stringify(input)} in base ${base}`,
		{
			decimal: result.decimal,
			hexadecimal: result.hexadecimal,
			binary: result.binary,
			hasError: typeof result.error === "string" && result.error.length > 0,
		},
		{ decimal: "", hexadecimal: "", binary: "", hasError: true },
	);
}

// BigInt is only the test oracle; the QML implementation uses plain JavaScript.
for (let i = 0; i < 100; i++) {
	const value =
		(BigInt(i) * 12345678901234567890123456789n) ** 2n * (i % 2 ? -1n : 1n);
	const expected = {
		decimal: value.toString(10),
		hexadecimal: value.toString(16).toUpperCase(),
		binary: value.toString(2),
		error: "",
	};
	for (const base of [2, 10, 16]) {
		check(
			`exact conversion ${i} from base ${base}`,
			model.convertInteger(value.toString(base), base),
			expected,
		);
	}
}

const large = BigInt("9".repeat(300));
for (const base of [2, 10, 16]) {
	check(
		`300-digit integer from base ${base}`,
		model.convertInteger(large.toString(base), base),
		{
			decimal: large.toString(10),
			hexadecimal: large.toString(16).toUpperCase(),
			binary: large.toString(2),
			error: "",
		},
	);
}

check("unit categories", model.unitCategories(), [
	{ id: "length", label: "Length" },
	{ id: "area", label: "Area" },
	{ id: "volume", label: "Volume" },
	{ id: "temperature", label: "Temperature" },
	{ id: "mass", label: "Mass" },
]);
check("unit category label", model.unitCategoryLabel("volume"), "Volume");
check("unit name", model.unitName("length", "mi"), "Miles (mi)");

const unitConversions = [
	["1", "length", "m", "ft", "3.28083989501312"],
	["5", "length", "km", "mi", "3.10685596118667"],
	["1", "area", "acre", "m2", "4046.8564224"],
	["1", "volume", "l", "gal", "0.264172052358148"],
	["1", "volume", "gal", "l", "3.785411784"],
	["0", "temperature", "c", "f", "32"],
	["32", "temperature", "f", "c", "0"],
	["273.15", "temperature", "k", "c", "0"],
	["-459.67", "temperature", "f", "k", "0"],
	["-40", "temperature", "c", "f", "-40"],
	["1", "mass", "kg", "lb", "2.20462262184878"],
	["-2", "mass", "kg", "lb", "-4.40924524369755"],
	[0, "length", "m", "ft", "0"],
	["12,5", "length", "m", "m", "12.5"],
];
unitConversions.forEach(([input, category, from, to, value]) =>
	check(
		`convertUnit(${input}, ${category}, ${from}, ${to})`,
		model.convertUnit(input, category, from, to),
		{ value, error: "" },
	),
);

for (const input of ["", "  "]) {
	check(`empty unit input ${JSON.stringify(input)}`, model.convertUnit(input, "length", "m", "ft"), {
		value: "",
		error: "",
	});
}

for (const [input, category, from, to] of [
	["1 + 2", "length", "m", "ft"],
	["1e3", "length", "m", "ft"],
	["NaN", "length", "m", "ft"],
	["1", "unknown", "m", "ft"],
	["1", "length", "m", "unknown"],
	["-274", "temperature", "c", "f"],
	["-460", "temperature", "f", "c"],
	["-1", "temperature", "k", "c"],
	["1" + "0".repeat(308), "mass", "tonne", "mg"],
]) {
	const result = model.convertUnit(input, category, from, to);
	check(
		`invalid unit conversion ${JSON.stringify(input)} ${category} ${from} ${to}`,
		{
			value: result.value,
			hasError: typeof result.error === "string" && result.error.length > 0,
		},
		{ value: "", hasError: true },
	);

	const dateCalculations = [
		["between", "2024-01-01", "2024-01-03", {
			value: "2 days",
			error: "",
			copy: "2 days",
			detail: "2024-01-01 to 2024-01-03: 2 days",
		}],
		["between", "2024-01-03", "2024-01-01", {
			value: "2 days",
			error: "",
			copy: "2 days",
			detail: "2024-01-03 to 2024-01-01: 2 days",
		}],
		["between", "2024-02-28", "2024-02-29", {
			value: "1 day",
			error: "",
			copy: "1 day",
			detail: "2024-02-28 to 2024-02-29: 1 day",
		}],
		["between", "2024-02-28", "2024-03-01", {
			value: "2 days",
			error: "",
			copy: "2 days",
			detail: "2024-02-28 to 2024-03-01: 2 days",
		}],
		["between", "2024-12-31", "2025-01-01", {
			value: "1 day",
			error: "",
			copy: "1 day",
			detail: "2024-12-31 to 2025-01-01: 1 day",
		}],
		["add", "2024-12-31", "1", {
			value: "2025-01-01",
			error: "",
			copy: "2025-01-01",
			detail: "2024-12-31 + 1 day = 2025-01-01",
		}],
		["add", "2024-03-01", "-1", {
			value: "2024-02-29",
			error: "",
			copy: "2024-02-29",
			detail: "2024-03-01 - 1 day = 2024-02-29",
		}],
		["add", "0001-01-01", "0", {
			value: "0001-01-01",
			error: "",
			copy: "0001-01-01",
			detail: "0001-01-01 + 0 days = 0001-01-01",
		}],
	];
	dateCalculations.forEach(([mode, first, second, expected]) =>
		check(
			`calculateDate(${mode}, ${first}, ${second})`,
			model.calculateDate(mode, first, second),
			expected,
		),
	);

	for (const [mode, first, second] of [
		["between", "2023-02-29", "2023-03-01"],
		["between", "2024-04-31", "2024-05-01"],
		["between", "10/13/2026", "2026-10-14"],
		["between", "2026-10-13", "2026-13-14"],
		["add", "2024-01-01", "1.5"],
		["add", "2024-01-01", "1e3"],
		["add", "2024-01-01", "9007199254740992"],
		["add", "9999-12-31", "1"],
		["add", "0001-01-01", "-1"],
		["unknown", "2024-01-01", "1"],
	]) {
		const result = model.calculateDate(mode, first, second);
		check(
			`invalid date calculation ${mode} ${first} ${second}`,
			{
				value: result.value,
				hasError: typeof result.error === "string" && result.error.length > 0,
			},
			{ value: "", hasError: true },
		);
	}
}

console.log(`${checks - failures}/${checks} checks passed`);
process.exit(failures === 0 ? 0 : 1);
