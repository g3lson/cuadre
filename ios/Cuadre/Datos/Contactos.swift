import SwiftUI
import ContactsUI

/// SACAR UN CLIENTE DE LA AGENDA.
///
/// Quien vende ya tiene a sus clientes en el teléfono: escribir «Doña Carmen
/// Rosa» y su número a mano es copiar algo que ya está.
///
/// El selector es de iOS y corre FUERA de la app: no hace falta permiso de
/// contactos y la app no ve la agenda, solo lo que la persona elija. Por eso se
/// usa este y no `CNContactStore`, que sí lo pediría.
///
/// **No se presenta desde un `.sheet` de SwiftUI.** Ese era el fallo: metido en
/// una hoja, al elegir un contacto el selector se cierra a sí mismo, y con él
/// se llevaba por delante la hoja del encargo que lo había abierto. El nombre
/// llegaba a los campos y medio segundo después la pantalla entera se cerraba,
/// así que no se guardaba nada. Se presenta desde UIKit, encima de lo que haya,
/// y al cerrarse no arrastra nada.
@MainActor
enum Contactos {
    /// El delegado de `CNContactPickerViewController` es débil: si no se guarda
    /// aquí, se libera nada más presentar y no llega ninguna respuesta.
    private static var enMarcha: Delegado?

    static func elige(_ alElegir: @escaping (String, String) -> Void) {
        guard let desde = elDeArriba() else { return }
        let d = Delegado { nombre, numero in
            alElegir(nombre, numero)
            enMarcha = nil
        } alCancelar: {
            enMarcha = nil
        }
        enMarcha = d

        let selector = CNContactPickerViewController()
        selector.delegate = d
        // Solo los que tienen teléfono: elegir uno sin número y que no pase
        // nada es peor que no verlo.
        selector.predicateForEnablingContact = NSPredicate(format: "phoneNumbers.@count > 0")
        selector.displayedPropertyKeys = [CNContactPhoneNumbersKey]
        desde.present(selector, animated: true)
    }

    /// El controlador que está encima de todo ahora mismo. Presentar desde la
    /// raíz cuando hay una hoja abierta no hace nada y no avisa.
    private static func elDeArriba() -> UIViewController? {
        let ventana = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }?
            .keyWindow
        var vc = ventana?.rootViewController
        while let arriba = vc?.presentedViewController { vc = arriba }
        return vc
    }

    private final class Delegado: NSObject, CNContactPickerDelegate {
        let alElegir: (String, String) -> Void
        let alCancelar: () -> Void

        init(alElegir: @escaping (String, String) -> Void, alCancelar: @escaping () -> Void) {
            self.alElegir = alElegir
            self.alCancelar = alCancelar
        }

        func contactPicker(_ picker: CNContactPickerViewController, didSelect contacto: CNContact) {
            let nombre = CNContactFormatter.string(from: contacto, style: .fullName)
                ?? [contacto.givenName, contacto.familyName].filter { !$0.isEmpty }.joined(separator: " ")
            // El móvil primero: es el que tiene WhatsApp.
            let telefonos = contacto.phoneNumbers
            let movil = telefonos.first {
                $0.label == CNLabelPhoneNumberMobile || $0.label == CNLabelPhoneNumberiPhone
            }
            let numero = (movil ?? telefonos.first)?.value.stringValue ?? ""
            alElegir(nombre, numero)
        }

        /// Elegir una propiedad suelta cuenta igual: quien toca el número de un
        /// contacto está eligiendo ese contacto.
        func contactPicker(_ picker: CNContactPickerViewController, didSelect propiedad: CNContactProperty) {
            let c = propiedad.contact
            let nombre = CNContactFormatter.string(from: c, style: .fullName) ?? c.givenName
            let numero = (propiedad.value as? CNPhoneNumber)?.stringValue
                ?? c.phoneNumbers.first?.value.stringValue ?? ""
            alElegir(nombre, numero)
        }

        func contactPickerDidCancel(_ picker: CNContactPickerViewController) {
            alCancelar()
        }
    }
}
