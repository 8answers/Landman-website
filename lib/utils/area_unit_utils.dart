/// Area unit conversion utilities.
/// Storage is always in sqft. Display/input conversion when user selects sqm.
/// 1 sqft = 0.092903 sqm
/// 1 sqm = 10.7639 sqft
class AreaUnitUtils {
  static const double sqftToSqm = 0.092903;
  static const double sqmToSqft = 10.7639;

  /// Convert area from stored sqft to display value based on selected unit.
  static double areaFromSqftToDisplay(double sqft, bool isSqm) {
    if (isSqm) return sqft * sqftToSqm;
    return sqft;
  }

  /// Convert area from display value to sqft for storage.
  static double areaFromDisplayToSqft(double displayValue, bool isSqm) {
    if (isSqm) return displayValue * sqmToSqft;
    return displayValue;
  }

  /// Convert rate (e.g. ₹/sqft) from stored value to display. 1 ₹/sqft = 10.7639 ₹/sqm.
  static double rateFromSqftToDisplay(double ratePerSqft, bool isSqm) {
    if (isSqm) return ratePerSqft * sqmToSqft;
    return ratePerSqft;
  }

  /// Convert rate from display to sqft for storage.
  static double rateFromDisplayToSqft(double displayRate, bool isSqm) {
    if (isSqm) return displayRate / sqmToSqft;
    return displayRate;
  }

  /// Get unit suffix for display (e.g. 'sqft' or 'sqm').
  static String unitSuffix(bool isSqm) => isSqm ? 'sqm' : 'sqft';

  /// Get per-area fee label for display (e.g. 'Per Sqft Fee' or 'Per Sqm Fee').
  static String perAreaFeeLabel(bool isSqm) => isSqm ? 'Per Sqm Fee' : 'Per Sqft Fee';

  /// Check if unit string represents sqm.
  static bool isSqm(String unit) =>
      unit.toLowerCase().contains('meter') || unit.toLowerCase().contains('sqm');
}
