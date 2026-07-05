/// User-selectable measurement units. All lengths are stored in centimetres;
/// this only affects how they are displayed and entered.
enum UnitSystem { metric, imperial }

extension UnitSystemX on UnitSystem {
  bool get isMetric => this == UnitSystem.metric;

  String get label =>
      isMetric ? 'Centimetres (cm)' : 'Feet & inches (ft / in)';

  String get shortLabel => isMetric ? 'cm' : 'ft / in';
}

const double _cmPerInch = 2.54;
const double _cmPerFoot = 30.48;

int cmToInches(double cm) => (cm / _cmPerInch).round();
double inchesToCm(num inches) => inches * _cmPerInch;

/// Formats a whole number of inches as feet-inches, e.g. 35 → 2′11″.
String _ftIn(int totalInches) {
  final neg = totalInches < 0;
  final t = totalInches.abs();
  final ft = t ~/ 12;
  final inch = t % 12;
  final String s;
  if (ft == 0) {
    s = '$inch″';
  } else if (inch == 0) {
    s = '$ft′';
  } else {
    s = '$ft′$inch″';
  }
  return neg ? '-$s' : s;
}

/// A length in centimetres, formatted for [system] with a unit suffix
/// (e.g. "90 cm" or "2′11″").
String formatLen(double cm, UnitSystem system) =>
    system.isMetric ? '${cm.round()} cm' : _ftIn(cmToInches(cm));

/// The measure only, no leading unit word, for compact spots (ruler ticks,
/// stepper values): "90" / "90 cm"-less, or "2′11″".
String formatLenValue(double cm, UnitSystem system) =>
    system.isMetric ? '${cm.round()} cm' : _ftIn(cmToInches(cm));

/// Width × height × depth for the chosen [system].
String formatDims(double w, double h, double d, UnitSystem system) =>
    system.isMetric
        ? '${w.round()}×${h.round()}×${d.round()} cm'
        : '${_ftIn(cmToInches(w))} × ${_ftIn(cmToInches(h))} × ${_ftIn(cmToInches(d))}';

/// Feet value for a length that is a whole number of feet (ruler foot marks).
String feetLabel(double cm) => '${(cm / _cmPerFoot).round()}′';

/// The centimetres represented by one foot / the imperial ruler minor step
/// (6 inches).
const double cmPerFoot = _cmPerFoot;
const double imperialRulerMinorCm = _cmPerInch * 6;
