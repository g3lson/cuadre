import SwiftUI
import ContactsUI

/// SACAR UN CLIENTE DE LA AGENDA.
///
/// Quien vende ya tiene a sus clientes en el teléfono: escribir «Doña Carmen
/// Rosa» y su número a mano es copiar algo que ya está. Se abre el selector del
/// sistema, se elige, y entra el nombre con el teléfono.
///
/// El selector es de iOS y corre fuera de la app: **no hace falta permiso de
/// contactos** y la app no ve la agenda, solo lo que la persona elija. Por eso
/// se usa este y no `CNContactStore`, que sí lo pediría.
struct SelectorDeContacto: UIViewControllerRepresentable {
    var alElegir: (String, String) -> Void

    func makeUIViewController(context: Context) -> CNContactPickerViewController {
        let c = CNContactPickerViewController()
        c.delegate = context.coordinator
        // Solo se ofrecen los que tienen teléfono: elegir uno sin número y que
        // no pase nada es peor que no verlo.
        c.predicateForEnablingContact = NSPredicate(format: "phoneNumbers.@count > 0")
        c.displayedPropertyKeys = [CNContactPhoneNumbersKey]
        return c
    }

    func updateUIViewController(_ c: CNContactPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinador { Coordinador(alElegir: alElegir) }

    final class Coordinador: NSObject, CNContactPickerDelegate {
        let alElegir: (String, String) -> Void
        init(alElegir: @escaping (String, String) -> Void) { self.alElegir = alElegir }

        func contactPicker(_ picker: CNContactPickerViewController, didSelect contacto: CNContact) {
            let nombre = CNContactFormatter.string(from: contacto, style: .fullName)
                ?? [contacto.givenName, contacto.familyName].filter { !$0.isEmpty }.joined(separator: " ")
            // El móvil primero: es el que tiene WhatsApp.
            let telefonos = contacto.phoneNumbers
            let movil = telefonos.first { $0.label == CNLabelPhoneNumberMobile || $0.label == CNLabelPhoneNumberiPhone }
            let numero = (movil ?? telefonos.first)?.value.stringValue ?? ""
            alElegir(nombre, numero)
        }

        /// Elegir una propiedad suelta cuenta igual: alguien que toca el número
        /// de un contacto está eligiendo ese contacto.
        func contactPicker(_ picker: CNContactPickerViewController, didSelect propiedad: CNContactProperty) {
            let c = propiedad.contact
            let nombre = CNContactFormatter.string(from: c, style: .fullName) ?? c.givenName
            let numero = (propiedad.value as? CNPhoneNumber)?.stringValue
                ?? c.phoneNumbers.first?.value.stringValue ?? ""
            alElegir(nombre, numero)
        }
    }
}
