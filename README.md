# Calculator

A keyboard-first Omarchy shell plugin with live arithmetic, exact integer base
conversion, live unit conversion, and date calculations. Open it from the
Calculator bar widget or run:

```sh
omarchy-shell shell toggle kb.calculator
```

## Installation and removal

Install and enable the plugin with:

```sh
omarchy plugin add https://github.com/adnahl/kb.calculator.git --enable
```

Remove it with:

```sh
omarchy plugin remove kb.calculator
```

The plugin requires the Omarchy shell. Clipboard actions use `wl-copy` from
the `wl-clipboard` package.

## Keyboard shortcut

To open the calculator with **SUPER + ALT + C**, add this binding to
`sudo nvim ~/.config/hypr/bindings.lua`:

```lua
o.bind("SUPER + ALT + C", "Calculator", "omarchy-shell shell toggle kb.calculator")
```

Hyprland reloads the binding automatically after you save the file. If needed,
reload the configuration with `hyprctl reload`.

## Calculator

Type an expression such as `(128 + 64) / 2`. Results update live.
Supported notation includes powers, parentheses, percentages, implicit
multiplication, `sqrt`, `abs`, `round`, `floor`, `ceil`, `pi`, and `e`.
The **Help** button contains the full notation reference.

- **Enter:** copy the result and close.
- **Ctrl+Enter / Shift+Enter:** copy the expression and result without closing.
- **Escape:** close help or the unit picker, then clear the input, then close the
  overlay.

## Base converter

Select **Base converter**, choose the input base, and type an integer.
Decimal, hexadecimal, and binary results update together.

| Input base | Example | Decimal | Hexadecimal | Binary |
| --- | --- | --- | --- | --- |
| Decimal | `255` | `255` | `FF` | `11111111` |
| Hexadecimal | `0x2A` | `42` | `2A` | `101010` |
| Binary | `-0b1010` | `-10` | `-A` | `-1010` |

Hexadecimal accepts upper- or lowercase digits and an optional `0x` prefix.
Binary accepts an optional `0b` prefix. Prefixes must match the selected input
base. Optional `+` and `-` signs and leading zeros are supported. Fractions,
expressions, separators, and scientific notation are not supported here.
Invalid input displays an error and disables copying.

Large integers are converted without floating-point rounding. Negative numbers
use a minus sign in every base, not a fixed-width two's-complement encoding.
Results omit prefixes; hexadecimal letters are uppercase.

- **Copy:** copy the adjacent result without closing.
- **Enter:** copy the decimal result and close.
- **Ctrl+Enter / Shift+Enter:** copy all three labeled results without closing.
- Long results scroll horizontally and can be selected with the mouse.

Changing the input base reinterprets the current text. Switching modes clears
the input. The overlay remembers the selected mode and input base until the
plugin reloads.

## Unit converter

Select **Unit converter**, choose a category, and enter a number. Choose the
source and target units to update the result live. Supported categories and
units:

- **Length:** millimeters, centimeters, meters, kilometers, inches, feet, yards,
  and miles.
- **Area:** square millimeters, square centimeters, square meters, square
  kilometers, square inches, square feet, square yards, acres, and hectares.
- **Volume:** milliliters, liters, cubic meters, and US teaspoons, tablespoons,
  fluid ounces, cups, pints, quarts, and gallons.
- **Temperature:** Celsius, Fahrenheit, and Kelvin.
- **Mass / weight:** milligrams, grams, kilograms, metric tonnes, ounces,
  pounds, and US short tons.

Use a decimal point or comma; expressions and scientific notation are not
supported. Temperatures below absolute zero are rejected.

- **Copy:** copy the converted value and unit without closing.
- **Enter:** copy the converted value and unit, then close.
- **Ctrl+Enter / Shift+Enter:** copy the input and converted value without
  closing.

Switching modes clears the input. The overlay remembers the selected mode,
category, and units until the plugin reloads.

## Date calculator

Select **Date calculator** to calculate elapsed days between two dates or add
and subtract a whole number of days from a date. Enter dates in `YYYY-MM-DD`
format; invalid dates and results outside `0001-01-01` to `9999-12-31` are
rejected. The difference is elapsed days, so the start date is not counted.
Use the subtle **Today** button beside a date field to fill in the local
system date.

- **Enter:** copy the result and close.
- **Ctrl+Enter / Shift+Enter:** copy the calculation details without closing.

Date calculations use calendar dates in UTC, so daylight-saving changes do not
affect the result.

## Development

User plugin files hot-reload on save. If the shell retains an older component,
run `omarchy restart shell` to clear its cache. The interface uses Omarchy theme
colors, spacing, typography, and shared button components.

Run the model regression tests:

```sh
node test/calc-model.test.js
```

## License

This plugin is licensed under the [MIT License](LICENSE).
