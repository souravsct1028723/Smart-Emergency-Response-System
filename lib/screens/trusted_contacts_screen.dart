import 'package:flutter/material.dart';

import '../models/trusted_contact.dart';
import '../services/trusted_contact_service.dart';

class TrustedContactsScreen extends StatefulWidget {
  const TrustedContactsScreen({super.key});

  @override
  State<TrustedContactsScreen> createState() =>
      _TrustedContactsScreenState();
}

class _TrustedContactsScreenState
    extends State<TrustedContactsScreen> {

  final List<TrustedContact> _contacts = [];

  static const int maxContacts = 5;

  @override
  void initState() {
    super.initState();
    _loadContacts();
  }
  
  Future<void> _loadContacts() async {
    final savedContacts =
      await TrustedContactService.loadContacts();

    if (!mounted) return;

    setState(() {
        _contacts.clear();
        _contacts.addAll(savedContacts);
    });
  }

  Future<void> _addContact() async {
    if (_contacts.length >= maxContacts) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Maximum 5 people can be added to the Emergency Circle.',
          ),
        ),
      );

      return;
    }

    final contact = await _showContactDialog();

    if (contact != null) {
        setState(() {
        _contacts.add(contact);
        });
    await TrustedContactService.saveContacts(_contacts);
    }
  }

  Future<void> _editContact(int index) async {
    final updatedContact = await _showContactDialog(
      existingContact: _contacts[index],
    );

    if (updatedContact != null) {
        setState(() {
        _contacts[index] = updatedContact;
    });

    await TrustedContactService.saveContacts(_contacts);
    }
  }

  Future<void> _deleteContact(int index) async {
    final contact = _contacts[index];

    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete Contact?'),
          content: Text(
            'Remove ${contact.name} from your Emergency Circle?',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context, false);
              },
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context, true);
              },
              child: const Text(
                'Delete',
                style: TextStyle(color: Colors.red),
              ),
            ),
          ],
        );
      },
    );

    if (shouldDelete == true) {
      setState(() {
        _contacts.removeAt(index);
      });
      await TrustedContactService.saveContacts(_contacts);
    }
  }

  Future<TrustedContact?> _showContactDialog({
    TrustedContact? existingContact,
  }) async {

    final nameController = TextEditingController(
      text: existingContact?.name ?? '',
    );

    final phoneController = TextEditingController(
      text: existingContact?.phoneNumber ?? '',
    );

    final isEditing = existingContact != null;

    final contact = await showDialog<TrustedContact>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(
            isEditing ? 'Edit Contact' : 'Add Contact',
          ),

          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [

              TextField(
                controller: nameController,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Name',
                  hintText: 'Example: Mother',
                  prefixIcon: Icon(Icons.person_outline),
                ),
              ),

              const SizedBox(height: 16),

              TextField(
                controller: phoneController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Phone Number',
                  hintText: 'Example: +91XXXXXXXXXX',
                  prefixIcon: Icon(Icons.phone_outlined),
                ),
              ),
            ],
          ),

          actions: [

            TextButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: const Text('Cancel'),
            ),

            ElevatedButton(
              onPressed: () {

                final name = nameController.text.trim();
                final phone = phoneController.text.trim();

                if (name.isEmpty || phone.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Please enter both name and phone number.',
                      ),
                    ),
                  );

                  return;
                }

                Navigator.pop(
                  context,
                  TrustedContact(
                    name: name,
                    phoneNumber: phone,
                  ),
                );
              },
              child: Text(
                isEditing ? 'Save' : 'Add',
              ),
            ),
          ],
        );
      },
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
        nameController.dispose();
        phoneController.dispose();
    });

    return contact;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Emergency Circle'),
      ),

      body: Padding(
        padding: const EdgeInsets.all(16),

        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,

          children: [

            const Text(
              'Emergency Circle',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 8),

            Text(
              'Add up to 5 people who should receive '
              'your emergency alerts.',
              style: TextStyle(
                fontSize: 15,
                color: Colors.grey.shade600,
              ),
            ),

            const SizedBox(height: 8),

            Text(
              '${_contacts.length}/$maxContacts contacts',
              style: const TextStyle(
                fontWeight: FontWeight.w600,
              ),
            ),

            const SizedBox(height: 16),

            Expanded(
              child: _contacts.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [

                          Icon(
                            Icons.people_outline,
                            size: 70,
                            color: Colors.grey.shade400,
                          ),

                          const SizedBox(height: 16),

                          const Text(
                            'No emergency contacts added',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                            ),
                          ),

                          const SizedBox(height: 8),

                          Text(
                            'Add people who should be notified '
                            'during an emergency.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      itemCount: _contacts.length,

                      itemBuilder: (context, index) {

                        final contact = _contacts[index];

                        return Card(
                          margin: const EdgeInsets.only(
                            bottom: 10,
                          ),

                          child: ListTile(
                            leading: const CircleAvatar(
                              child: Icon(
                                Icons.person,
                              ),
                            ),

                            title: Text(
                              contact.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),

                            subtitle: Text(
                              contact.phoneNumber,
                            ),

                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [

                                IconButton(
                                  icon: const Icon(
                                    Icons.edit_outlined,
                                  ),

                                  onPressed: () {
                                    _editContact(index);
                                  },
                                ),

                                IconButton(
                                  icon: const Icon(
                                    Icons.delete_outline,
                                    color: Colors.red,
                                  ),

                                  onPressed: () {
                                    _deleteContact(index);
                                  },
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),

            const SizedBox(height: 12),

            SizedBox(
              width: double.infinity,

              child: OutlinedButton.icon(
                onPressed: _addContact,

                icon: const Icon(
                  Icons.add,
                ),

                label: const Text(
                  'Add Contact',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}