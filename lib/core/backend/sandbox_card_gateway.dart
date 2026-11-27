import '../hotel_store.dart';

/// Stand-in for the card gateway's SDK while the backend gateway runs in sandbox mode (US-15): the card never leaves
/// the device; only the token of a test card is sent to the API (`POST /bookings/{id}/payments/card`).
class SandboxCardGateway {
  const SandboxCardGateway._();

  /// Test cards and the sandbox token each one stands for.
  static const Map<String, String> testCards = {
    '4242424242424242': 'tok_visa',
    '5555555555554444': 'tok_mastercard',
    '4000000000009995': 'tok_declined_insufficient_funds',
    '4000000000000069': 'tok_declined_expired_card',
    '4000000000000002': 'tok_declined_card',
  };

  /// Checks the form and returns the token of the card. Throws [DomainException] with the field to fix.
  static String tokenize(CardInfo card) {
    final digits = card.digits;
    if (digits.length < 13 || digits.length > 19) throw const DomainException('Revisa el número de la tarjeta.');
    if (card.holder.trim().length < 3) throw const DomainException('Ingresa el nombre del titular.');
    final expiry = RegExp(r'^(0[1-9]|1[0-2])/(\d{2})$').firstMatch(card.expiry.trim());
    if (expiry == null) throw const DomainException('La fecha de vencimiento va como MM/AA.');
    if (!RegExp(r'^\d{3,4}$').hasMatch(card.cvv.trim())) throw const DomainException('El CVV tiene 3 o 4 dígitos.');
    final token = testCards[digits];
    if (token == null) {
      throw const DomainException('Modo de prueba: usa 4242 4242 4242 4242 (aprobada) o 4000 0000 0000 0002 (rechazada).');
    }
    return token;
  }
}
