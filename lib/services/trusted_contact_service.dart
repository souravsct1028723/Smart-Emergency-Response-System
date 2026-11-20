import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/trusted_contact.dart';

class TrustedContactService {
  static const String _contactsKey = 'emergency_circle_contacts';

  static Future<void> saveContacts(
    List<TrustedContact> contacts,
  ) async {
    final prefs = await SharedPreferences.getInstance();

    final contactList = contacts.map((contact) {
      return {
        'name': contact.name,
        'phoneNumber': contact.phoneNumber,
      };
    }).toList();

    final jsonString = jsonEncode(contactList);

    await prefs.setString(
      _contactsKey,
      jsonString,
    );
  }

  static Future<List<TrustedContact>> loadContacts() async {
    final prefs = await SharedPreferences.getInstance();

    final jsonString = prefs.getString(_contactsKey);

    if (jsonString == null || jsonString.isEmpty) {
      return [];
    }

    try {
      final List<dynamic> decodedList = jsonDecode(jsonString);

      return decodedList.map((item) {
        return TrustedContact(
          name: item['name'],
          phoneNumber: item['phoneNumber'],
        );
      }).toList();
    } catch (e) {
      print(
        'TRUSTED CONTACT SERVICE: Failed to load contacts: $e',
      );

      return [];
    }
  }

  static Future<void> clearContacts() async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.remove(_contactsKey);
  }
}