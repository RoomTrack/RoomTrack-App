import 'package:flutter/material.dart';

import '../../core/backend/remote_extras.dart';

/// Text fields of a phone and an address (staff and guest records).
class ContactControllers {
  final phone = TextEditingController();
  final street = TextEditingController();
  final number = TextEditingController();
  final city = TextEditingController();
  final postalCode = TextEditingController();
  final country = TextEditingController();

  void fill(ContactData data) {
    phone.text = data.phone;
    street.text = data.street;
    number.text = data.number;
    city.text = data.city;
    postalCode.text = data.postalCode;
    country.text = data.country;
  }

  ContactData get value => ContactData(
        phone: phone.text,
        street: street.text,
        number: number.text,
        city: city.text,
        postalCode: postalCode.text,
        country: country.text,
      );

  void dispose() {
    for (final c in [phone, street, number, city, postalCode, country]) {
      c.dispose();
    }
  }
}

class ContactFields extends StatelessWidget {
  final ContactControllers controllers;

  const ContactFields({super.key, required this.controllers});

  @override
  Widget build(BuildContext context) {
    final c = controllers;
    return Column(
      children: [
        TextField(
          controller: c.phone,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(labelText: 'Teléfono', prefixIcon: Icon(Icons.phone_outlined)),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(flex: 3, child: TextField(controller: c.street, decoration: const InputDecoration(labelText: 'Calle'))),
            const SizedBox(width: 8),
            Expanded(child: TextField(controller: c.number, decoration: const InputDecoration(labelText: 'N.º'))),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(child: TextField(controller: c.city, decoration: const InputDecoration(labelText: 'Ciudad'))),
            const SizedBox(width: 8),
            Expanded(child: TextField(controller: c.postalCode, decoration: const InputDecoration(labelText: 'Código postal'))),
            const SizedBox(width: 8),
            Expanded(child: TextField(controller: c.country, decoration: const InputDecoration(labelText: 'País'))),
          ],
        ),
      ],
    );
  }
}
