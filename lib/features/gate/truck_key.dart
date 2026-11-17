/// A truck number in a form that can be COMPARED: the key that pairs a gate
/// record with a truck row on the same pile point.
///
/// Two people type the same number differently — "TM 1000", "tm1000",
/// "1000", "TM-A984". Only letters and digits are kept, upper-cased, with a
/// leading "TM" dropped.
///
/// Mirrors `truck_key` in the backend's `controllers/field_controller.py`,
/// which is what actually decides the pairing; this copy only keeps a
/// number the log already used out of the list offered to the person at
/// the hole. Empty input gives "", and "" never pairs with anything.
String truckKey(String? number) {
  final clean = (number ?? '').toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
  if (clean.startsWith('TM') && clean.length > 2) return clean.substring(2);
  return clean;
}
