class FirestorePaths {
  static String users() => 'users';
  static String user(String uid) => 'users/$uid';
  static String households() => 'households';
  static String household(String id) => 'households/$id';
  static String rooms(String householdId) => 'households/$householdId/rooms';
  static String room(String householdId, String roomId) =>
      'households/$householdId/rooms/$roomId';
  static String units(String householdId) => 'households/$householdId/units';
  static String unit(String householdId, String unitId) =>
      'households/$householdId/units/$unitId';
  static String slots(String householdId) => 'households/$householdId/slots';
  static String slot(String householdId, String slotId) =>
      'households/$householdId/slots/$slotId';
  static String items(String householdId) => 'households/$householdId/items';
  static String item(String householdId, String itemId) =>
      'households/$householdId/items/$itemId';
  static String products(String householdId) =>
      'households/$householdId/products';
  static String product(String householdId, String barcode) =>
      'households/$householdId/products/$barcode';
}
